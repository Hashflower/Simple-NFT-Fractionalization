// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";


interface IRICKS {
function mintFrac(address _frac, uint256 _amount) external;
function balanceOf(address account) external returns (uint256);
function totalSupply() external returns (uint256);
function transferFrom(address from,address to,uint256 amount) external returns (bool);
function transfer(address to, uint256 amount) external returns (bool);
}

contract FRAC is Ownable {
using SafeERC20 for IERC20;

    //variables, nothing fancy
    address public token;
    address public NFT;
    uint256 public initShares1;
    uint256 public initShares2;
    address public scheduler;
    uint256 public majorityThreshold = 80e18;
    uint256 public topMajorityThreshold = 100e18;

    // main struct for the lock records
    struct LockRecord {
        uint256 lockTime;
        uint256 id;
        address one;
        address two;
        uint256 initSharesOne;
        uint256 initSharesTwo;
        uint256 initSupply;
        uint256 initialized;
        uint256 canBeSold;
        uint256 buyoutPrice;
        address mainShareHolder;
        uint256 lockedShares;
    }
    
    // each locks assigned to a mapping
    mapping(address => LockRecord) public lockrecord;

    //restrict the mint
    modifier onlyScheduler() {
        require(scheduler == msg.sender, "Caller is not the scheduler");
        _;
    }
    
    // hard coded init shares as per instructions
    constructor (        
        address _NFT,
        address _token
    ) public {
        NFT = _NFT;
        token = _token;
        initShares1 = 5000e18;
        initShares2 = 5000e18;
    }

    /* =================== Get functions =================== */
    //front end peeps
    function getLockRecords(address _NFT) public view returns (uint256,uint256,address,address,uint256,uint256,uint256,uint256,uint256,uint256,address,uint256) {
        LockRecord storage lr = lockrecord[_NFT];
        return (lr.lockTime,lr.id,lr.one,lr.two,lr.initSharesOne,lr.initSharesTwo,lr.initSupply,lr.initialized,lr.canBeSold,lr.buyoutPrice,lr.mainShareHolder,lr.lockedShares);
    }

    //front end peeps
    function getInitialSupplyOf(address _NFT) public view returns (uint256) {
        LockRecord storage lr = lockrecord[NFT];
        return lr.initSupply;
    }
    
    /* =================== Set Functions =================== */

    function setScheduler(address _scheduler) public onlyOwner {
        require(_scheduler != address(0), "madlad");
        scheduler = _scheduler;
    }

    function setInitShares(uint256 _initShares1, uint256 _initShares2) public onlyOwner {
        initShares1 = _initShares1;
        initShares2 = _initShares2;
    }

    function setThresholds(uint256 _majorityThreshold, uint256 _topMajorityThreshold) public onlyOwner {
        require(_majorityThreshold > 80e18 && _topMajorityThreshold > 95e18, "nonono");
        majorityThreshold = _majorityThreshold;
        topMajorityThreshold = _topMajorityThreshold;
    }

    /* =================== Restricted Functions =================== */

    function _mintToScheduler(uint256 _amount) public onlyScheduler {
        require(msg.sender == scheduler, "madlad");
        IRICKS(token).mintFrac(scheduler, _amount);
    }

    //lock any type of NFT
    //possible improvement : make the function public and create an instance of an ERC20 for different locked NFT
    //potentially a good "factory" implementation to allow users to lock any NFTs and emit any shares

    function lockNFT(address _NFT, uint256 _id, address _address1, address _address2) public onlyOwner {
        LockRecord storage lr = lockrecord[_NFT];
        IERC721(_NFT).transferFrom(msg.sender, address(this), _id);

        lr.lockTime = block.timestamp;
        lr.id = _id;
        lr.one = _address1;
        lr.two = _address2;
        lr.initSharesOne = initShares1;
        lr.initSharesTwo = initShares2;
        lr.initSupply = lr.initSharesOne + lr.initSharesTwo;

        IRICKS(token).mintFrac(lr.one, lr.initSharesOne);
        IRICKS(token).mintFrac(lr.two, lr.initSharesTwo);
    }

    // returns the current shares of a specific user
    function ret(address _sender) public returns(uint256){
        uint256 userBal = IRICKS(token).balanceOf(_sender);
        uint256 shareCalc = (userBal * 1e18 / IRICKS(token).totalSupply()) * 100;
        return(shareCalc);
    }

    // put an NFT for sell
    // specify a sell price
    // sender mush have majorityThreshold > of shares to be able to exec
    function setNFTForSell(address _NFT, uint256 _buyoutPrice) public {
        LockRecord storage lr = lockrecord[_NFT];
        // we check the users shares
        uint256 shareCalc = ret(msg.sender);
        require(shareCalc > majorityThreshold, "you aint the major shareholder");
        require(lr.canBeSold == 0, "already for sale");
        
        lr.canBeSold = 1;
        lr.buyoutPrice = _buyoutPrice;
        lr.mainShareHolder = msg.sender;
        lr.lockedShares = IRICKS(token).balanceOf(msg.sender);
        //we lock all shares while the NFT is for sell
        IRICKS(token).transferFrom(msg.sender, address(this), lr.lockedShares);
    }


    // cancel the sell, must be for sale and the sell initiator
    function cancelNFTSell(address _NFT) public {
        LockRecord storage lr = lockrecord[_NFT];
        require(lr.canBeSold == 1, "not for sale");
        require(msg.sender == lr.mainShareHolder, "not the main shareholder");
        lr.canBeSold = 0;
        lr.buyoutPrice = 0;
        //fuzzzz
        uint256 shares = lr.lockedShares;
        lr.lockedShares = 0;
        IRICKS(token).transfer(msg.sender, shares);
    }

    // anyone can buy main shares
    // change of ownership on ERC20 side
    function buyMainSharesOfNFT(address _NFT) public payable {
        LockRecord storage lr = lockrecord[_NFT];
        require(lr.canBeSold == 1, "not for sale");
        require(msg.value >= lr.buyoutPrice);
        lr.canBeSold = 0;
        lr.buyoutPrice = 0;
        //fuzzzz
        uint256 shares = lr.lockedShares;
        lr.lockedShares = 0;
        IRICKS(token).transfer(msg.sender, shares);
        lr.mainShareHolder = msg.sender;
    }

    // unlock the NFT is the sender has 100% of shares
    // could implement a 99% threshold with randomness and chainlink... 
    function claimNFT(address _NFT) public {
        LockRecord storage lr = lockrecord[_NFT];
        uint256 shareCalc = ret(msg.sender);
        require(shareCalc >= topMajorityThreshold, "you aint the 100% shareholder");
        require(lr.canBeSold == 0, "cancel sell order first");
        lr.buyoutPrice = 0;
        lr.lockedShares = 0;
        lr.mainShareHolder = address(0);
        giveAllowance(_NFT, msg.sender, lr.id);
        IERC721(_NFT).transferFrom(address(this), msg.sender, lr.id);
    }

    function giveAllowance(address _NFT, address _sender, uint256 _id) internal {
        IERC721(_NFT).approve(_sender, _id);
    }

}
