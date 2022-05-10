// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
// import './Math.sol';
import './SafeMath.sol';
import './TransferHelper.sol';
import './IERC20.sol';

contract EcioStaking {
    using SafeMath  for uint;

    struct UserInfo {
        uint256 amount;
        uint256 rewarded;
        uint256 rewardDebt;
        uint256 lastCalculatedTimeStamp;
        uint256 lastDepositTimeStamp;
        uint256 lockedDay;
    }

    // pool info
    address public lpToken;
    // IERC20 lpToken;
    uint256 public totalAmount;

    address public rewardToken;
    address public adminAddress;
    // Reward tokens created per Sec.
    uint256 public rewardRate;
    

    uint256 public totalAmountLockDay;
    // Info of each user that stakes LP tokens.
    // mapping (address => UserInfo) public userInfo;
    mapping (address => mapping (uint => UserInfo)) public userInfo;
    mapping(address => mapping (address => uint256)) allowed;
    address[] public userList;
    mapping(address => uint) public userlistNum;
    uint private unlocked = 1;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Reward(address indexed user, uint256 amount);

    constructor(
        address _lpToken,
        // IERC20 _lpToken,
        address _rewardToken
    ) public {
        adminAddress = msg.sender;
        lpToken = _lpToken;
        rewardToken = _rewardToken;
        totalAmount = 0;
        totalAmountLockDay = 0;
    }

    function setAdmin(address _adminAddress) public {
        require(adminAddress == msg.sender, "not Admin");
        adminAddress = _adminAddress;
    }

    function userStakingCounter(address _useraddress) public view returns (uint256) {
        return userlistNum[_useraddress];
    }

    function userCounter() public view returns (uint256) {
        return userList.length;
    }

    function useraddress(uint256 userNum) public view returns (address) {
        return userList[userNum];
    }

    function stakedLp(uint userStakingNum) public view returns (uint256) {
        UserInfo storage user = userInfo[msg.sender][userStakingNum];
        return user.amount;
    }

    function multiplier(uint256 lockDays) public view returns (uint256) {
        if(lockDays == 30) return 10;
        if(lockDays == 60) return 15;
        if(lockDays == 90) return 20;
        if(lockDays == 120) return 30;
        if(lockDays == 240) return 40;
        if(lockDays == 360) return 50;
    }

    function stakingPeriod(uint userStakingNum) public view returns (uint256) {
        UserInfo storage user = userInfo[msg.sender][userStakingNum];
        return user.lockedDay;
    }

    function earnEcio(uint userStakingNum) public view returns (uint256) {
        UserInfo storage user = userInfo[msg.sender][userStakingNum];
        return user.rewarded;
    }

    function lockDate(uint userStakingNum) public view returns (uint256) {
        UserInfo storage user = userInfo[msg.sender][userStakingNum];
        return user.lastDepositTimeStamp;
    }

    function stakingStatus(uint userStakingNum) public view returns (bool) {
        UserInfo storage user = userInfo[msg.sender][userStakingNum];
        if(user.lastDepositTimeStamp + user.lockedDay * 1 days > block.timestamp) return false;
        else return true;
    }

    // function updatePool() internal {
    //     for(uint i = 0 ; i < userList.length ; i ++){
    //         UserInfo storage user = userInfo[userList[i]];
    //         uint256 lastTimeStamp = block.timestamp;
    //         if(user.lastCalculatedTimeStamp + 1 days <= lastTimeStamp){
    //             // user.lastDepositTimeStamp = lastTimeStamp;
    //             uint256 accDebt = (user.amount * multiplier(user.lockedDay) * (1e6) * (1e18)) / totalAmountLockDay;
    //             user.rewardDebt = user.rewardDebt.add(accDebt);
    //             user.lastCalculatedTimeStamp = lastTimeStamp;
    //         }
    //     }
    // }

    function updatePool() internal {
        for(uint i = 0 ; i < userList.length ; i ++){
            for(uint j = 0 ; j < userlistNum[userList[i]] ; j ++){
                UserInfo storage user = userInfo[userList[i]][j];
                uint256 lastTimeStamp = block.timestamp;
                if(user.lastCalculatedTimeStamp + 1 days <= lastTimeStamp){
                    uint256 accDebt = (user.amount * multiplier(user.lockedDay) * (1e6) * (1e18)) / totalAmountLockDay;
                    user.rewardDebt = user.rewardDebt.add(accDebt);
                    user.lastCalculatedTimeStamp = lastTimeStamp;
                }
            }
        }
    }

    function deposit(uint256 amount, uint256 lockDay) public {
        require(amount > 0, "invaild amount");
        TransferHelper.safeTransferFrom(lpToken, msg.sender, address(this), amount);
        // UserInfo storage user = userInfo[msg.sender];
        bool isFirst = true;
        for (uint i = 0; i < userList.length; i++) {
            if (userList[i] == msg.sender) {
                isFirst = false;
            }
        }
        updatePool();
        if (isFirst) {
            UserInfo storage user = userInfo[msg.sender][0];
            userlistNum[msg.sender] = 1;
            userList.push(msg.sender);
            user.amount = amount;
            user.rewarded = 0;
            user.rewardDebt = 0;
            user.lastDepositTimeStamp = block.timestamp;
            user.lastCalculatedTimeStamp = block.timestamp;
            user.lockedDay = lockDay;            
        } else {
            UserInfo storage user = userInfo[msg.sender][userlistNum[msg.sender]];
            userlistNum[msg.sender] = userlistNum[msg.sender] + 1;
            user.amount = user.amount + amount;
            user.lastDepositTimeStamp = block.timestamp;
            user.lastCalculatedTimeStamp = block.timestamp;
            user.lockedDay = lockDay;
        }
        totalAmount = totalAmount + amount;
        totalAmountLockDay = totalAmountLockDay.add(amount * multiplier(lockDay));
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint userStakingNum) public {
        UserInfo storage user = userInfo[msg.sender][userStakingNum];
        require(user.lastDepositTimeStamp > 0, "invalid user");
        require(user.amount > 0, "not staked");
        require(user.lastDepositTimeStamp + user.lockedDay * 1 days < block.timestamp, "you are in lockedTime.");
        updatePool();
        TransferHelper.safeTransfer(lpToken, msg.sender, user.amount);
        totalAmount = totalAmount - user.amount;
        user.amount = 0;
        user.rewarded = user.rewarded + user.rewardDebt;
        user.rewardDebt = 0;
        emit Withdraw(msg.sender, user.amount);
    }

    function rewardUpdate(uint userStakingNum) public {
        UserInfo storage user = userInfo[msg.sender][userStakingNum];
        updatePool();
        user.rewarded = user.rewarded + user.rewardDebt;
        user.rewardDebt = 0;
    }

    function claim(uint userStakingNum) public {
        UserInfo storage user = userInfo[msg.sender][userStakingNum];
        updatePool();
        uint amount = user.rewardDebt;
        // require(amount > 0, "not enough reward amount");
        user.rewarded = user.rewarded + amount;
        user.rewardDebt = 0;
        TransferHelper.safeTransfer(rewardToken, msg.sender, amount);
        emit Reward(msg.sender, amount);
    }
}