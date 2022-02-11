pragma solidity 0.8.7;
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {IBoardroom} from "./interfaces/IBoardroom.sol";


interface IFRAC {
    function getInitialSupplyOf(address _NFT) external view returns (uint256);
    function _mintToScheduler(uint256 _amount) external;
}

interface IRICKS {
function mintFrac(address _frac, uint256 _amount) external;
function balanceOf(address account) external returns (uint256);
function totalSupply() external returns (uint256);
function transferFrom(address from,address to,uint256 amount) external returns (bool);
function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

contract ScheduledMinter is ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    /* ========= CONSTANT VARIABLES ======== */
    uint256 public constant PERIOD = 24 hours;

    /* ========== STATE VARIABLES ========== */

    // governance
    address public operator;
    address public NFT;

    // flags
    bool public migrated;
    bool public initialized;

    // epoch
    uint256 public startTime;
    uint256 public epoch;
    uint256 public percent;

    // tokens and board
    address public FRAC;
    address public RICKS;
    address public unirouter;
    address public WETH;
    address public boardroom;
    uint256 public initBid;
    uint256 public auctionDelay;
    
    // auctions records
    struct Auctions{
        uint256 amountMinted;
        uint256 auctionId;
        uint256 startedAt;
        uint256 currentBid;
        uint256 wethRaised;
        uint256 delay;
        bool isActive;
        address lastBidder;
    }

    mapping(uint256 => Auctions) public auctions;


    /* =================== Events =================== */
    //could implement more events, stayed minimalistic 
    event Initialized(address indexed executor, uint256 at);
    event BoardroomFunded(uint256 timestamp, uint256 seigniorage);

    //==========================================//

    /* =================== Modifier =================== */

    modifier onlyOperator() {
        require(operator == msg.sender, "Caller is not the operator");
        _;
    }

    function checkCondition() private {
        require(block.timestamp >= startTime, "Not started yet");
    }

    function checkEpoch() private  {
        require(block.timestamp >= nextEpochPoint(), "Not opened yet");
    }

    function checkOperator() private {
        require(
               IBoardroom(boardroom).getOperator() == address(this), 
            "Need more permission"
        );
    }

    /* ========== View Functions ========== */


    function isInitialized() public view returns (bool) {
        return initialized;
    }

    // epoch
    function nextEpochPoint() public view returns (uint256) {
        return startTime.add(epoch.mul(PERIOD));
    }


    /* ========== Governance ========== */

    function initialize(
        address _FRAC,
        address _RICKS,
        address _WETH,
        uint256 _startTime,
        address _NFT
    )  public {
        require(!initialized, "Initialized");
        FRAC = _FRAC;
        RICKS = _RICKS;
        WETH = _WETH;
        NFT = _NFT;
        startTime = _startTime;
        epoch = 0;
        percent = 1;
        initBid = 0.1 ether;
        //delay set at 0 for testing purpose
        auctionDelay = 200;

        initialized = true;
        operator = msg.sender;
        emit Initialized(msg.sender, block.number);
    }

    /* =================== Set Functions =================== */

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setBoardroom(address _boardroom) external onlyOperator {
        boardroom = _boardroom;
    }

    function setAuctionDelay(uint256 _auctionDelay) public onlyOperator {
        require(_auctionDelay > 0, "madlad");
        auctionDelay = _auctionDelay;
    }

    function setinitBid(uint256 _initBid) public onlyOperator {
        require(_initBid > 0, "madlad");
        initBid = _initBid;
    }

    function setPercentMint(uint256 _percent) public onlyOperator {
        require(_percent > 0, "madlad");
        percent = _percent;
    }

    function setCoreAddresses(address _FRAC, address _WETH, address _RICKS) external onlyOperator {
        FRAC = _FRAC;
        WETH = _WETH;
        RICKS = _RICKS;
    }

    function _sendToBoardRoom(uint256 _amount) internal {
        IERC20Upgradeable(WETH).safeApprove(boardroom, _amount);
        IBoardroom(boardroom).allocateSeigniorage(_amount);
        emit BoardroomFunded(block.timestamp, _amount);
    }

    /* =================== Some Other View Stuff =================== */

    function viewRICKS() public view returns (uint256) {
        uint256 bal = IERC20Upgradeable(RICKS).balanceOf(address(this));
        return(bal);
    }

    function viewInitSupply() public view returns (uint256) {
       uint256 init = IFRAC(FRAC).getInitialSupplyOf(NFT);
       return init;
    }

    function getAuction(uint256 _epoch) public view returns(uint256,uint256,uint256,uint256,uint256,uint256,bool,address) {
        Auctions storage a = auctions[_epoch];
        return (
        a.amountMinted,
        a.auctionId,
        a.startedAt,
        a.currentBid,
        a.wethRaised,
        a.delay,
        a.isActive,
        a.lastBidder);
    }

    function isAuctionEnded() public view returns (bool) {
        Auctions storage a = auctions[epoch];
        if (block.timestamp > a.delay) {
            return true;
        } else if (block.timestamp < a.delay) {
            return false;
        }
    }

/* =================== Core Logic =================== */

    function mintAndAuction() public {
        Auctions storage a = auctions[epoch];
        // check if all conditions are met
       
         checkEpoch();

        //in any case, we mint
        uint256 supply = viewInitSupply();
        uint256 toMint = (supply * percent) / 100;
        IFRAC(FRAC)._mintToScheduler(toMint);

        // we check if current auction has been filled
        //if no, still active, no we add more to the pot
        if (a.isActive == true) {

        a.amountMinted = a.amountMinted + toMint;

        // otherwise, we add 1 epoch, start a new auction
        } else {

        epoch = epoch.add(1);
        Auctions storage b = auctions[epoch];
        b.amountMinted = toMint;
        b.auctionId = epoch;
        b.startedAt = block.timestamp;
        b.currentBid = initBid;
        b.isActive = true;
        b.delay = block.timestamp + auctionDelay;
        }
    }

    // anyone can bid, auction ends when no one bids
    // time limit of auctionDelay (200 seconds) for tests, more reasonable at 1hour IMO
    function bid() public payable {
        Auctions storage a = auctions[epoch];
        require(msg.value >= a.currentBid, "Pay more awee");
        require(block.timestamp <= a.delay,  "Too late!");
        a.currentBid = msg.value;
        //as we will use erc20 later in the board, convert now to ease transfers
        //we keep payable to make users life easy
        IWETH(WETH).deposit{value: msg.value}();
        uint256 wethbal = IERC20Upgradeable(WETH).balanceOf(address(this));
        a.wethRaised = wethbal;
        a.delay = block.timestamp + auctionDelay;
        a.lastBidder = msg.sender;
    }

    // to be triggered with a web3 script, check isAuctionEnded() for true or false
    // if true, operator can exec endAuction and distribute the shares accordingly
    // also sends WETH to the boardroom that will be claimed by shareholders
    // another alternative : imbric endAuction in the bid function with an if statement
    // but consume more gas... TBD
    function endAuction() public onlyOperator {
        Auctions storage a = auctions[epoch];
        require(block.timestamp >= a.delay,  "Still on!");
        a.isActive = false;
        IERC20Upgradeable(RICKS).transfer(a.lastBidder, a.amountMinted);
        allocateRICKSToBoardroom();
    }

    function allocateRICKSToBoardroom() internal {
        checkOperator();
        Auctions storage a = auctions[epoch];
        require(a.wethRaised > 0,  "eeer");
        _sendToBoardRoom(a.wethRaised);   
    }


    /* ========== BOARDROOM CONTROLLING FUNCTIONS ========== */

    function boardroomSetOperator(address _operator) external onlyOperator {
        IBoardroom(boardroom).setOperator(_operator);
    }

    function boardroomAllocateSeigniorage(uint256 amount) external onlyOperator {
        IBoardroom(boardroom).allocateSeigniorage(amount);
    }

    function boardroomGovernanceRecoverUnsupported(address _token,uint256 _amount,address _to) external onlyOperator {
        IBoardroom(boardroom).governanceRecoverUnsupported(_token, _amount, _to);
    }


}
