pragma solidity 0.6.12;

import '@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol';

import '../Milky.sol';

// MasterChef is the master of Milky. He can make Milky and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once MILKY is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 claimId;
        uint256 lastClaimed;
        //
        // We do some fancy math here. Basically, any point in time, the amount of MILKYs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accMilkyPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accMilkyPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    struct UserClaim {
        uint256 locked;
        uint256 claimTime;
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. MILKYs to distribute per block.
        uint256 totalDeposited;   // Total amount of tokens deposited into the pool.
        uint256 lastRewardBlock;  // Last block number that MILKYs distribution occurs.
        uint256 accMilkyPerShare; // Accumulated MILKYs per share, times 1e12. See below.
    }

    // The MILKY TOKEN!
    Milky public milky;
    // Dev address.
    address public devaddr;
    // MILKY tokens created per block.
    uint256 public milkyPerBlock;
    // Bonus muliplier for early milky makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // The reward claim delay
    uint256 public CLAIM_DELAY = 90 days;
    // The reward claim cooldown
    uint256 public CLAIM_COOLDOWN = 24 hours;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    mapping (uint256 => mapping (address => UserClaim[])) public userClaim;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when MILKY mining starts.
    uint256 public startBlock;
    // Check if deposits are allowed
    bool public isPaused;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        Milky _milky,
        address _devaddr,
        uint256 _milkyPerBlock,
        uint256 _startBlock
    ) public {
        milky = _milky;
        devaddr = _devaddr;
        milkyPerBlock = _milkyPerBlock;
        startBlock = _startBlock;
        totalAllocPoint = 0;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate) public onlyOwner {
        bool exists = false;
        for (uint256 i = 0; i < poolInfo.length; i++) {
            if (poolInfo[i].lpToken == _lpToken) {
                exists = true;
                break;
            }
        }

        require(!exists, "add: already exists");
        
        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            totalDeposited: 0,
            lastRewardBlock: lastRewardBlock,
            accMilkyPerShare: 0
        }));
    }

    // Update the given pool's MILKY allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;

        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    function getAccMilkyPerShare(PoolInfo storage pool) internal view returns (uint256) {
        uint256 accMilkyPerShare = pool.accMilkyPerShare;
        uint256 lpSupply = pool.totalDeposited;

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 milkyReward = multiplier.mul(milkyPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accMilkyPerShare = accMilkyPerShare.add(milkyReward.mul(1e12).div(lpSupply));
        }

        return accMilkyPerShare;
    }

    // View function to see pending MILKYs on frontend.
    function pendingMilky(uint256 _pid, address _user) external view returns (uint256, uint256, uint256, uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        UserClaim[] storage userClaims = userClaim[_pid][_user];

        uint256 accMilkyPerShare = getAccMilkyPerShare(pool);
        uint256 rewards = user.amount.mul(accMilkyPerShare).div(1e12).sub(user.rewardDebt);
        uint256 instant = rewards.mul(25).div(100);
        uint256 locked = rewards.sub(instant);
        uint256 unlocked = 0;

        for (uint256 i = user.claimId; i < userClaims.length; i++) {
            rewards = rewards.add(userClaims[i].locked);
            if (userClaims[i].claimTime.add(CLAIM_DELAY) <= block.timestamp) {
                unlocked = unlocked.add(userClaims[i].locked);
            } else {
                locked = locked.add(userClaims[i].locked);
            }
        }

        return (rewards, instant, locked, unlocked);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        uint256 lpSupply = pool.totalDeposited;

        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 milkyReward = multiplier.mul(milkyPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

        milky.mintTo(devaddr, milkyReward.div(10));
        milky.mintTo(address(this), milkyReward);
        pool.accMilkyPerShare = pool.accMilkyPerShare.add(milkyReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    function claimRewards(uint256 _pid, address _user, uint256 pending) internal {
        UserInfo storage user = userInfo[_pid][_user];
        
        if (user.lastClaimed.add(CLAIM_COOLDOWN) <= block.timestamp) {
            UserClaim[] storage userClaims = userClaim[_pid][_user];

            uint256 claimId = user.claimId;
            uint256 rewards = 0;

            for (uint256 i = claimId; i < userClaims.length; i++) {
                if (userClaims[i].claimTime.add(CLAIM_DELAY) <= block.timestamp) {
                    rewards = rewards.add(userClaims[i].locked);
                    userClaims[i].locked = 0;
                    claimId = i + 1;
                }
            }

            if (pending > 0) {
                uint256 locked = pending.mul(75).div(100);
                rewards = rewards.add(pending.sub(locked));

                UserClaim memory claimInfo = UserClaim(locked, block.timestamp);
                userClaims.push(claimInfo);
            }

            user.claimId = claimId;

            if (rewards > 0) {
                user.lastClaimed = block.timestamp;
                safeMilkyTransfer(msg.sender, rewards);
            }
        }
    }

    // Deposit LP tokens to MasterChef for MILKY allocation.
    function deposit(uint256 _pid, uint256 _amount) external whenNotPaused {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accMilkyPerShare).div(1e12).sub(user.rewardDebt);
        claimRewards(_pid, msg.sender, pending);

        if (_amount > 0) {
            uint256 balBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 balAfter = pool.lpToken.balanceOf(address(this));
            uint256 actualReceived = balAfter.sub(balBefore);

            user.amount = user.amount.add(actualReceived);
            pool.totalDeposited = pool.totalDeposited.add(actualReceived);
        }

        user.rewardDebt = user.amount.mul(pool.accMilkyPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accMilkyPerShare).div(1e12).sub(user.rewardDebt);
        claimRewards(_pid, msg.sender, pending);
        
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalDeposited = pool.totalDeposited.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }

        user.rewardDebt = user.amount.mul(pool.accMilkyPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external whenPaused {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 oldUserAmount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        pool.totalDeposited = pool.totalDeposited.sub(oldUserAmount);
        pool.lpToken.safeTransfer(address(msg.sender), oldUserAmount);
        emit EmergencyWithdraw(msg.sender, _pid, oldUserAmount);
    }

    // Safe milky transfer function, just in case if rounding error causes pool to not have enough MILKYs.
    function safeMilkyTransfer(address _to, uint256 _amount) internal {
        uint256 milkyBal = milky.balanceOf(address(this));
        if (_amount > milkyBal) {
            milky.transfer(_to, milkyBal);
        } else {
            milky.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) external {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    // Set the paused variable by the owner
    function setPaused(bool paused) external onlyOwner {
        isPaused = paused;
    }

    // Set the reward claim delay by the owner
    function setClaimDelay(uint256 delay) external onlyOwner {
        require(delay >= 90 days && delay <= 360 days,
            "delay: not within bounds");
        CLAIM_DELAY = delay;
    }

    // Set the reward claim cooldown by the owner
    function setClaimCooldown(uint256 cooldown) external onlyOwner {
        require(cooldown <= 3 days,
            "cooldown: not within bounds");
        CLAIM_COOLDOWN = cooldown;
    }

    modifier whenPaused {
        require(isPaused,
            "pause: disabled");

        _;
    }

    modifier whenNotPaused {
        require(!isPaused,
            "pause: enabled");

        _;
    }
}
