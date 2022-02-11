

pragma solidity 0.8.7;
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";


interface IScheduledMinter {
    function epoch() external view returns (uint256);
    function nextEpochPoint() external view returns (uint256);
}

// Share wrapper contract that controls the RICKS tokens in contract
contract ShareWrapper {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public share;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        share.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        uint256 directorShare = _balances[msg.sender];
        require(directorShare >= amount, "Boardroom: withdraw request greater than staked amount");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = directorShare.sub(amount);
        share.safeTransfer(msg.sender, amount);
    }
}

// Classic board contract, with upgradeable functionalities
// Can also be used for voting, eventually in a scenario in which buyouts wanna be contested...
contract Boardroom is ShareWrapper, ReentrancyGuardUpgradeable {
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== Data Structures ========== */

    struct Boardseat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
        uint256 epochTimerStart;
    }

    struct BoardSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    /* ========== State Variables ========== */

    // governance
    address public operator;

    // flags
    bool public initialized;
    address public WETH;
    address public ScheduledMinter;

    mapping(address => Boardseat) public directors;
    BoardSnapshot[] public boardHistory;

    /* ========== Events ========== */

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);

    /* ========== Modifiers =============== */

    modifier onlyOperator() {
        require(operator == msg.sender, "Boardroom: caller is not the crem lord");
        _;
    }

    modifier directorExists {
        require(balanceOf(msg.sender) > 0, "Boardroom: The director does not exist");
        _;
    }

    modifier updateReward(address director) {
        if (director != address(0)) {
            Boardseat memory seat = directors[director];
            seat.rewardEarned = earned(director);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            directors[director] = seat;
        }
        _;
    }

    modifier notInitialized {
        require(!initialized, "Boardroom: already initialized");
        _;
    }

    /* ========== Governance and setup ========== */
    // we initialize the board with all parameters
    function initialize(
        IERC20Upgradeable _IRICKS,
        address _WETH,
        address _ScheduledMinter
    ) public notInitialized {
        WETH = _WETH;
        share = _IRICKS;
        ScheduledMinter = _ScheduledMinter;
        BoardSnapshot memory genesisSnapshot = BoardSnapshot({time: block.number, rewardReceived: 0, rewardPerShare: 0});
        boardHistory.push(genesisSnapshot);

        initialized = true;
        operator = msg.sender;

        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setWETHToken(address _WETHToken) public onlyOperator {
        require(address(0) != _WETHToken, "Boardroom: MADLAD");
        WETH = _WETHToken;
    }

    /* ========== View functions ========== */

    function latestSnapshotIndex() public view returns (uint256) {
        return boardHistory.length.sub(1);
    }

    function getLatestSnapshot() internal view returns (BoardSnapshot memory) {
        return boardHistory[latestSnapshotIndex()];
    }

    function getOperator() public view returns (address) {
        return operator;
    }

    function getLastSnapshotIndexOf(address director) public view returns (uint256) {
        return directors[director].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address director) internal view returns (BoardSnapshot memory) {
        return boardHistory[getLastSnapshotIndexOf(director)];
    }

    function epoch() external view returns (uint256) {
        return IScheduledMinter(ScheduledMinter).epoch();
    }

    function nextEpochPoint() external view returns (uint256) {
        return IScheduledMinter(ScheduledMinter).nextEpochPoint();
    }


    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function earned(address director) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(director).rewardPerShare;

        return balanceOf(director).mul(latestRPS.sub(storedRPS)).div(1e18).add(directors[director].rewardEarned);
    }

    /* ========== Core Logic ========== */

    function stake(uint256 amount) public override nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Stake 0 ? Ape!!");
        super.stake(amount);
        directors[msg.sender].epochTimerStart = IScheduledMinter(ScheduledMinter).epoch(); // reset timer
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public override nonReentrant directorExists updateReward(msg.sender) {
        require(amount > 0, "Withdraw 0 ? Ape!!");
        address[] memory add;
        claimReward();
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
    }

    function claimReward() public updateReward(msg.sender) {
        uint256 reward = directors[msg.sender].rewardEarned;
        
        directors[msg.sender].epochTimerStart = IScheduledMinter(ScheduledMinter).epoch(); // reset timer
        directors[msg.sender].rewardEarned = 0;
        IERC20Upgradeable(WETH).safeTransfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
        
    }

    function allocateSeigniorage(uint256 amount) external nonReentrant onlyOperator {
        require(amount > 0, "Boardroom: Cannot allocate 0");
        require(totalSupply() > 0, "Boardroom: Cannot allocate when totalSupply is 0");

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(totalSupply()));

        BoardSnapshot memory newSnapshot = BoardSnapshot({time: block.number, rewardReceived: amount, rewardPerShare: nextRPS});
        boardHistory.push(newSnapshot);

        IERC20Upgradeable(WETH).safeTransferFrom(msg.sender, address(this), amount);
        emit RewardAdded(msg.sender, amount);
    }


}
