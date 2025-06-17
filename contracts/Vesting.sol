// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract Vesting is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable{
    
    using SafeERC20 for IERC20;

    struct Grant {
        uint256 startTime;
        uint256 amount;
        uint256 vestingDuration;
        uint256 monthsClaimed;
        uint256 totalClaimed;
        address recipient;
    }

    event GrantAdded(address indexed recipient);
    event GrantTokensClaimed(address indexed recipient, uint256 amountClaimed);
    event GrantRevoked(
        address recipient,
        uint256 amountVested,
        uint256 amountNotVested
    );
    event GrantUpdateAmount(
        address recipient,
        uint256 tokenAmount,
        uint256 amount
    );
    event MonthTimeUpdated(uint256 _intervalTime);
    event WithdrawToken(
        address indexed token,
        address indexed to,
        uint256 amount
    );
    event StartTimeChanged(
        address[] indexed recipients,
        uint256[] newStartTimes,
        uint256[] newVestingDurations
    );

    IERC20 public token;

    mapping(address => Grant) public tokenGrants;

    address public crowdsale_address;
    uint256 public monthTimeInSeconds;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { 
         _disableInitializers();
    }

    function  initialize (IERC20 _token) public initializer {
        require(address(_token) != address(0), "Invalid token address");

        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();     
        __ReentrancyGuard_init(); 
        token = _token;
        monthTimeInSeconds = 120 seconds; 
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    modifier onlyCrowdsale() {
        require(
            msg.sender == crowdsale_address,
            "Only crowdsale contract can call this function"
        );
        _;
    }

    function addCrowdsaleAddress(address crowdsaleAddress) external onlyOwner {
        require(
            crowdsaleAddress != address(0),
            "ERC20: transfer from the zero address"
        );
        crowdsale_address = crowdsaleAddress;
    }
    

    function addTokenGrant(
    address _recipient,
    uint256 _amount,
    uint256 initialLock, // initialLock is the waiting period (in seconds) after the token purchase 
    //during which no tokens can be claimed, even though the sale is completed.
    uint256 _vestingDurationInMonths
    //bool _isFounder
    ) external nonReentrant onlyCrowdsale {
    require(_recipient != address(0), "Invalid recipient address");
    require(_vestingDurationInMonths <= 25 * 12, "Duration > 25 years");
    require(_vestingDurationInMonths != 0, "Vesting duration = 0");
    require(_amount != 0, "Amount = 0");

    uint256 amountVestedPerMonth = _amount / _vestingDurationInMonths;
    require(amountVestedPerMonth > 0, "amountVestedPerMonth = 0");

      if (tokenGrants[_recipient].amount == 0) {
        Grant memory grant = Grant({
            startTime: currentTime() + initialLock + monthTimeInSeconds,
            amount: _amount,
            vestingDuration: _vestingDurationInMonths,
            monthsClaimed: 0,
            totalClaimed: 0,
            recipient: _recipient
          
        });
        tokenGrants[_recipient] = grant;
        emit GrantAdded(_recipient);
    } else {
        Grant storage tokenGrant = tokenGrants[_recipient];
        require(
            tokenGrant.monthsClaimed < tokenGrant.vestingDuration,
            "Grant fully claimed"
        );
        tokenGrant.amount += _amount;

        emit GrantUpdateAmount(_recipient, tokenGrant.amount, _amount);
    }
}


    function claimVestedTokens() external nonReentrant {
          uint256 monthsVested;
          uint256 amountVested;
          (monthsVested, amountVested) = calculateGrantClaim(msg.sender);
          require(amountVested > 0, "Vested = 0");

          Grant storage tokenGrant = tokenGrants[msg.sender];
          tokenGrant.monthsClaimed += monthsVested;
          tokenGrant.totalClaimed += amountVested;

          emit GrantTokensClaimed(tokenGrant.recipient, amountVested);
          token.transfer(tokenGrant.recipient, amountVested);
    }
  
    function getTotalGrantClaimed(address _recipient) external view returns (uint256, uint256) {
        Grant storage tokenGrant = tokenGrants[_recipient];
        return (tokenGrant.monthsClaimed, tokenGrant.totalClaimed);
}
  

    function revokeTokenGrant(address _recipient) external nonReentrant onlyOwner {
        Grant storage tokenGrant = tokenGrants[_recipient];

        uint256 monthsVested;
        uint256 amountVested;
        (monthsVested, amountVested) = calculateGrantClaim(_recipient);

        uint256 amountNotVested = tokenGrant.amount - tokenGrant.totalClaimed - amountVested;

    // Delete the grant from mapping
        delete tokenGrants[_recipient];

        emit GrantRevoked(_recipient, amountVested, amountNotVested);

    // Transfer tokens back to treasury/crowdsale and recipient
        if (amountNotVested > 0) {
            token.transfer(crowdsale_address, amountNotVested);
        }
        if (amountVested > 0) {
            token.transfer(_recipient, amountVested);
        }
      }
    

    function getGrantStartTime(address _recipient) external view returns (uint256) {
        Grant storage tokenGrant = tokenGrants[_recipient];
        return tokenGrant.startTime;
    }
    
    function getGrantAmount(address _recipient) external view returns (uint256) {
        Grant storage tokenGrant = tokenGrants[_recipient];
        return tokenGrant.amount;
    }
     
    function calculateGrantClaim(address _recipient) public view returns (uint256, uint256) {
        Grant storage tokenGrant = tokenGrants[_recipient];

        require(
            tokenGrant.totalClaimed < tokenGrant.amount,
            "Grant fully claimed"
        );

    // Check if lock duration was reached
        if (currentTime() < tokenGrant.startTime) {
            return (0, 0);
        }

    // Calculate elapsed months since the vesting start time
        uint256 elapsedMonths = ((currentTime() - tokenGrant.startTime) / monthTimeInSeconds) + 1;

    // If the vesting period is over, return remaining amount
        if (elapsedMonths > tokenGrant.vestingDuration) {
            uint256 remainingGrant = tokenGrant.amount - tokenGrant.totalClaimed;
            uint256 balanceMonth = tokenGrant.vestingDuration - tokenGrant.monthsClaimed;
            return (balanceMonth, remainingGrant);
        }

    // Otherwise, calculate vested tokens so far
         uint256 monthsVested = elapsedMonths - tokenGrant.monthsClaimed;
         uint256 amountVestedPerMonth = tokenGrant.amount / tokenGrant.vestingDuration;
         uint256 amountVested = monthsVested * amountVestedPerMonth;

         return (monthsVested, amountVested);
        }

    function updateMonthsTime(
        uint256 _intervalTime
    ) external onlyOwner nonReentrant {
        monthTimeInSeconds = _intervalTime;
        emit MonthTimeUpdated(monthTimeInSeconds);
    }

    function currentTime() private view returns (uint256) {
        return block.timestamp;
    }

    function remainingToken(
        address _recipient
    ) external view returns (uint256) {
        Grant storage tokenGrant = tokenGrants[_recipient];
        return tokenGrant.amount - tokenGrant.totalClaimed;
    }

    function nextClaimDate(
        address _recipient
    ) external view returns (uint256) {
        Grant storage tokenGrant = tokenGrants[_recipient];
        if (tokenGrant.startTime == 0) {
            return 0;
        }
        uint256 startTimeOfUser = tokenGrant.startTime;
        uint256 finalDate = startTimeOfUser +
            ((tokenGrant.vestingDuration - 1) * monthTimeInSeconds);
        if (block.timestamp > finalDate) {
            return finalDate;
        }
        if (block.timestamp < startTimeOfUser) {
            return startTimeOfUser;
        }
        while (startTimeOfUser <= block.timestamp) {
            startTimeOfUser += monthTimeInSeconds;
        }
        return startTimeOfUser;
    }

   
    function withdrawToken(
        address _tokenContract,
        uint256 _amount
    ) external onlyOwner nonReentrant {
        require(_tokenContract != address(0), "Address cant be zero address");
        IERC20 tokenContract = IERC20(_tokenContract);
        tokenContract.safeTransfer(msg.sender, _amount);
        emit WithdrawToken(_tokenContract, msg.sender, _amount);
    }

    // function withdrawEther(
    //     address payable _to,
    //     uint256 _amount
    // ) external onlyOwner nonReentrant {
    //     require(_to != address(0), "Invalid recipient address");
    //     require(_amount > 0, "Amount must be greater than 0");
    //     require(
    //         address(this).balance >= _amount,
    //         "Insufficient Ether balance in the contract"
    //     );

    //     // Transfer the specified amount of Ether to the recipient
    //     _to.transfer(_amount);
    // }

  
    function changeStartTime(
        address[] calldata _recipient,
        uint256[] calldata _startTime,
        uint256[] calldata _totalVestingMonths
    ) external onlyOwner nonReentrant {
        require(_recipient.length == _startTime.length, "Invalid parameters");
        require(_recipient.length == _totalVestingMonths.length, "Invalid parameters");

        for (uint256 index = 0; index < _recipient.length; index++) {
            require(_recipient[index] != address(0), "Invalid recipient address");
            require(_startTime[index] > 0, "Invalid start time");
            require(_totalVestingMonths[index] <= 25 * 12, "Duration > 25 years");

        Grant storage tokenGrant = tokenGrants[_recipient[index]];
        uint256 amountVestedPerMonth = tokenGrant.amount / _totalVestingMonths[index];
        require(amountVestedPerMonth > 0, "amountVestedPerMonth < 0");

        tokenGrant.startTime = _startTime[index];
        tokenGrant.vestingDuration = _totalVestingMonths[index];
        }

        emit StartTimeChanged(_recipient, _startTime, _totalVestingMonths);
    }


}