// ============ Contracts ============
const chalk = require('chalk');

const ScheduledMinter = artifacts.require('ScheduledMinter');
const RICKS = artifacts.require('RICKS');
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
const approve = new BigNumber(10000000000000e18);

await deployer.deploy(NFT);
const nft = await NFT.deployed();
console.log(nft.address);

await deployer.deploy(RICKS, "RICKS", "RICKS");
const ricks = await RICKS.deployed();

await deployer.deploy(FRAC, nft.address, ricks.address);
const frac = await FRAC.deployed();
await ricks.setFrac(frac.address);

await deployer.deploy(WETH);
const weth = await WETH.deployed();

const scheduler = await deployProxy(ScheduledMinter, [frac.address, ricks.address, weth.address, 1644563684,nft.address], { deployer, initializer: 'initialize' });
const board = await deployProxy(Boardroom, [ricks.address, weth.address, scheduler.address], { deployer, initializer: 'initialize' });
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
await scheduler.bid({value: 1e18});
//console.log(await scheduler.getAuction(1));

console.log("approve board");
await ricks.approve(board.address,approve);
console.log("stake in board");
await board.stake(new BigNumber(1e18));

console.log("set nft for sell");
await ricks.approve(frac.address, approve);
console.log(await frac.getLockRecords(nft.address))

//await frac.setNFTForSell(nft.address, new BigNumber(1e18));
// console.log(await frac.getLockRecords());
}
