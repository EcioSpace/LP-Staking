// SPDX-License-Identifier: MIT

import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";


// File: contracts/EcioLPStaking.sol

pragma solidity 0.8.4;


contract EcioLPStaking is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;       // How many LP tokens the user has provided.
        uint256 rewardDebt;   // Reward debt.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;                    // Address of LP token contract.
        uint256 perBlockEcioAllocated;      // Number of Ecio to distribute per block.
        uint256 lastRewardBlock;           // Last block number that Ecios distribution occurs.
        uint256 accEcioPerShare;            // Accumulated Ecios per share, times 1e12. See below.
    }

    // Address of Ecio token contract.
    IERC20 public ecioTokenContract;
    // Ecio tokens created per block.
    uint256 public ecioRewardPerBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocEcioPerBlock = 0;
    // The block number when Ecio mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event ContractFunded(address indexed from, uint256 amount);

    constructor(
        IERC20 _ecioContractAddress,
        uint256 _ecioPerBlock,
        uint256 _startBlock
    ) public {
        ecioTokenContract = _ecioContractAddress;
        ecioRewardPerBlock = _ecioPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function add(uint256 _ecioPerBlock, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocEcioPerBlock = totalAllocEcioPerBlock.add(_ecioPerBlock);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            perBlockEcioAllocated: _ecioPerBlock,
            lastRewardBlock: lastRewardBlock,
            accEcioPerShare: 0
            }));
    }

    // Update the given pool's Ecio per block. Can only be called by the owner.
    function set(uint256 _poolId, uint256 _ecioPerBlock, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocEcioPerBlock = totalAllocEcioPerBlock.sub(poolInfo[_poolId].perBlockEcioAllocated).add(_ecioPerBlock);
        poolInfo[_poolId].perBlockEcioAllocated = _ecioPerBlock;
    }

    // fund the contract with Ecio. _from address must have approval to execute Ecio Token Contract transferFrom
    function fund(address _from, uint256 _amount) public {
        require(_from != address(0), 'fund: must pass valid _from address');
        require(_amount > 0, 'fund: expecting a positive non zero _amount value');
        require(ecioTokenContract.balanceOf(_from) >= _amount, 'fund: expected an address that contains enough Ecio for Transfer');
        ecioTokenContract.transferFrom(_from, address(this), _amount);
        emit ContractFunded(_from, _amount);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending Ecios on frontend.
    // (user.amount * pool.accEcioPerShare) - rewardDebt
    function pendingEcioReward(uint256 _poolId, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_poolId];
        UserInfo storage user = userInfo[_poolId][_user];
        uint256 accEcioPerShare = pool.accEcioPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply < 0) {
            return 0;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 ecioReward = multiplier.mul(ecioRewardPerBlock).mul(pool.perBlockEcioAllocated).div(totalAllocEcioPerBlock);
        accEcioPerShare = accEcioPerShare.add(ecioReward.mul(1e12).div(lpSupply));
        return user.amount.mul(accEcioPerShare).div(1e12).sub(user.rewardDebt);
    }

    // View function to see contract held Ecio on frontend.
    function getLockedEcioView() external view returns (uint256) {
        return ecioTokenContract.balanceOf(address(this));
    }

    // View function to see pool held LP Tokens
    function getLpSupply(uint256 _poolId) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_poolId];
        return pool.lpToken.balanceOf(address(this));
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update pool supply and reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _poolId) public {
        PoolInfo storage pool = poolInfo[_poolId];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 ecioReward = multiplier.mul(ecioRewardPerBlock).mul(pool.perBlockEcioAllocated).div(totalAllocEcioPerBlock);
        pool.accEcioPerShare = pool.accEcioPerShare.add(ecioReward.mul(1e12).div(lpSupply));

        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to Contract for Ecio allocation.
    function deposit(uint256 _poolId, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_poolId];
        UserInfo storage user = userInfo[_poolId][msg.sender];
        updatePool(_poolId);
        // if user already has LP tokens in the pool execute harvest for the user
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accEcioPerShare).div(1e12).sub(user.rewardDebt);
            safeEcioTransfer(msg.sender, pending);
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accEcioPerShare).div(1e12);

        emit Deposit(msg.sender, _poolId, _amount);
    }

    // Withdraw LP tokens from Contract.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accEcioPerShare).div(1e12).sub(user.rewardDebt);

        safeEcioTransfer(address(msg.sender), pending);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accEcioPerShare).div(1e12);

        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
    }

    // Safe Ecio transfer function, just in case if rounding error causes pool to not have enough Ecios.
    function safeEcioTransfer(address _to, uint256 _amount) internal {
        address _from = address(this);
        uint256 ecioBal = ecioTokenContract.balanceOf(_from);
        if (_amount > ecioBal) {
            ecioTokenContract.transfer(_to, ecioBal);
        } else {
            ecioTokenContract.transfer(_to, _amount);
        }
    }
}