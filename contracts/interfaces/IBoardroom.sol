//SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

interface IBoardroom {

    function setFRACToken(address _FRACToken) external;
    function stake(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function claimReward() external;
    function exit() external;
    function allocateSeigniorage(uint256 amount) external;
    function setOperator(address _operator) external;
    function setLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external;
    function governanceRecoverUnsupported(address _token,uint256 _amount,address _to) external;
    function getOperator() external view returns (address);
}
