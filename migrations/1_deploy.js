// ============ Contracts ============
const chalk = require('chalk');

const ScheduledMinter = artifacts.require('ScheduledMinter');
const Boardroom = artifacts.require('Boardroom');
const FRAC = artifacts.require('FRAC');
const WETH = artifacts.require('WETH');
const NFT = artifacts.require('NFT');

const BigNumber = require('bignumber.js');
const { deployProxy } = require('@openzeppelin/truffle-upgrades');

// ============ Main Migration ============

const migration = async (deployer, network, accounts) => {


  await Promise.all([deployToken(deployer, network, accounts)])
}

module.exports = migration


async function deployToken(deployer, network, accounts) {
const DEPLOYER_ADDRESS = accounts[0];

await deployer.deploy(NFT);
const nft = await NFT.deployed();

await deployer.deploy(FRAC, "FRAC", "FRAC", nft.address);
const frac = await FRAC.deployed();

await deployer.deploy(WETH);
const weth = await WETH.deployed();

const scheduler = await deployProxy(ScheduledMinter, [frac.address, weth.address, 1644563684,nft.address], { deployer, initializer: 'initialize' });
const board = await deployProxy(Boardroom, [weth.address, frac.address, weth.address, scheduler.address], { deployer, initializer: 'initialize' });
//setup
await frac.setScheduler(scheduler.address);
await scheduler.setBoardroom(board.address);
await board.setOperator(scheduler.address);

//start
console.log("Approve");
await nft.approve(frac.address,0);
console.log("Lock");
await frac.lockNFT(nft.address,0,DEPLOYER_ADDRESS,DEPLOYER_ADDRESS);
console.log("minting");
await scheduler.mintAndAuction();
console.log("buy");
await scheduler.bid({value: 1});
console.log(await scheduler.getAuction(1));

}
