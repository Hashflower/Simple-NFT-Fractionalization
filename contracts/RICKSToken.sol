// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract RICKS is ERC20, Ownable {
using SafeERC20 for IERC20;

    address public frac;

    modifier onlyFrac() {
        require(frac == msg.sender, "Caller is not the scheduler");
        _;
    }

    constructor (        
        string memory _name, 
        string memory _symbol
    ) public ERC20(
        string(abi.encodePacked(_name)),
        string(abi.encodePacked(_symbol))
    ) {
    }

    function mintFrac(address _scheduler, uint256 _amount) public onlyFrac {
        _mint(_scheduler, _amount);
    }

    function setFrac(address _frac) public onlyOwner {
        frac = _frac;
    }



}
