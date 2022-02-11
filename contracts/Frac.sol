// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract FRAC is ERC20, Ownable {
using SafeERC20 for IERC20;


    
    IERC20 public token;
    address public NFT;
    uint256 public initShares1;
    uint256 public initShares2;
    address public scheduler;

    struct LockRecord {
        uint256 lockTime;
        uint256 id;
        address one;
        address two;
        uint256 initSharesOne;
        uint256 initSharesTwo;
        uint256 initSupply;
        uint256 initialized;
    }
    
    mapping(address => LockRecord) public lockrecord;

    modifier onlyScheduler() {
        require(scheduler == msg.sender, "Caller is not the scheduler");
        _;
    }
    

    constructor (        
        string memory _name, 
        string memory _symbol,
        address _NFT
    ) public ERC20(
        string(abi.encodePacked(_name)),
        string(abi.encodePacked(_symbol))
    ) {
        NFT = NFT;
        initShares1 = 5000e18;
        initShares2 = 5000e18;
    }

    function setScheduler(address _scheduler) public onlyOwner {
        require(_scheduler != address(0), "madlad");
        scheduler = _scheduler;
    }

    function getInitialSupplyOf(address _NFT) public view returns (uint256) {
        LockRecord storage lr = lockrecord[NFT];
        return lr.initSupply;
    }

    function setInitShares(uint256 _initShares1, uint256 _initShares2) public onlyOwner {
        initShares1 = _initShares1;
        initShares2 = _initShares2;
    }

    function _mintToScheduler(uint256 _amount) public onlyScheduler {
        require(msg.sender == scheduler, "madlad");
        _mint(scheduler, _amount);
    }

    //lock any type of NFT
    //possible improvement : create an instance of an ERC20 for different locked NFT
    //potentially a good "factory" implementation to allow users to lock any NFTs and emit any shares

    function lockNFT(address _NFT, uint256 _id, address _address1, address _address2) public {
        LockRecord storage lr = lockrecord[_NFT];
        IERC721(_NFT).transferFrom(msg.sender, address(this), _id);

        lr.lockTime = block.timestamp;
        lr.id = _id;
        lr.one = _address1;
        lr.two = _address2;
        lr.initSharesOne = initShares1;
        lr.initSharesTwo = initShares2;
        lr.initSupply = lr.initSharesOne + lr.initSharesTwo;

        _mint(lr.one, lr.initSharesOne);
        _mint(lr.two, lr.initSharesTwo);
    }





}
