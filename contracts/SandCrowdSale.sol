// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./Vesting.sol";

interface IERC20Extented is IERC20 {
    function decimals() external view returns (uint8);
}

contract SandCrowdSale is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    IERC20 public rewardToken;
    IERC20 public usdtToken;
    Vesting public vestingToken;

    uint256 public rate;
    uint256 public usdtRaised;
    uint256 public vestingMonths;
    uint256 public initialLockInPeriodInSeconds;

    uint256 public openingTime;
    uint256 public closingTime;
    bool public isFinalized;

    uint256 public taxOnBuy; // in basis points (e.g. 200 = 2%)
    address public donationWallet;

    struct UserInfo {
        uint256 usdtContributed;
        uint256 SandReceived;
    }

    mapping(address => UserInfo) public users;

    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);
    event TimedCrowdsaleExtended(uint256 prevClosingTime, uint256 newClosingTime);
    event Finalized();
    event WithdrawToken(address token, address to, uint256 amount);
    event TaxSettingsUpdated(uint256 buyTax);
    event DonationWalletUpdated(address newWallet);

    modifier onlyWhileOpen() {
        require(block.timestamp >= openingTime && block.timestamp <= closingTime, "Crowdsale not active");
        _;
    }

    function initialize(
        uint256 _rate,
        IERC20 _token,
        IERC20 _usdtToken,
        uint256 _openingTime,
        uint256 _closingTime,
        Vesting _vesting
    ) public initializer {
        require(_rate > 0, "Rate must be > 0");
        require(_openingTime >= block.timestamp, "Opening time must be future");
        require(_closingTime >= _openingTime, "Closing time must be after opening");

        rewardToken = _token;
        usdtToken = _usdtToken;
        vestingToken = _vesting;
        rate = _rate;
        vestingMonths = 2;
        initialLockInPeriodInSeconds = 300;

        openingTime = _openingTime;
        closingTime = _closingTime;

        taxOnBuy = 200; // 2%
        donationWallet = msg.sender;

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init_unchained();
        __Pausable_init();
    }

    function buyToken(address _beneficiary, uint256 usdtAmount) external onlyWhileOpen whenNotPaused nonReentrant {
        require(_beneficiary != address(0), "Beneficiary can't be zero");
        require(usdtAmount > 0, "USDT amount must be > 0");

        // Transfer full USDT from buyer
        usdtToken.safeTransferFrom(msg.sender, address(this), usdtAmount);

        // Calculate tax in USDT
        uint256 usdtTaxAmount = (usdtAmount * taxOnBuy) / 10000;
        uint256 netUsdtAmount = usdtAmount - usdtTaxAmount;

        // Send USDT tax to donation wallet
        if (usdtTaxAmount > 0) {
            usdtToken.safeTransfer(donationWallet, usdtTaxAmount);
        }

        // Calculate token amount based on net USDT
        uint256 tokens = _getTokenAmount(netUsdtAmount);

        usdtRaised += usdtAmount;

        users[_beneficiary].usdtContributed += usdtAmount;
        users[_beneficiary].SandReceived += tokens;

        // Transfer tokens to vesting contract
        rewardToken.safeTransfer(address(vestingToken), tokens);

        // Add vesting grant
        vestingToken.addTokenGrant(
            _beneficiary,
            tokens,
            initialLockInPeriodInSeconds,
            vestingMonths
        );

        emit TokenPurchase(msg.sender, _beneficiary, usdtAmount, tokens);
    }


    function _getTokenAmount(uint256 _usdtAmount) internal view returns (uint256) {
        return (_usdtAmount * rate * 1e18) / 1e6;
    }

    function extendSale(uint256 newClosingTime) external onlyOwner whenNotPaused {
        require(!isFinalized, "Already finalized");
        require(newClosingTime >= openingTime, "Invalid new time");
        require(newClosingTime > closingTime, "New time must be after current");

        emit TimedCrowdsaleExtended(closingTime, newClosingTime);
        closingTime = newClosingTime;
    }

    function finalize() external onlyOwner whenNotPaused {
        require(!isFinalized, "Already finalized");
        require(block.timestamp > closingTime, "Sale not closed yet");

        uint256 balance = rewardToken.balanceOf(address(this));
        require(balance > 0, "No tokens to finalize");

        rewardToken.safeTransfer(owner(), balance);

        emit Finalized();
        isFinalized = true;
    }

    function changeRate(uint256 newRate) external onlyOwner onlyWhileOpen whenNotPaused {
        require(newRate > 0, "Rate must be > 0");
        rate = newRate;
    }

    function changeInitialLockInPeriodInSeconds(uint256 newPeriod) external onlyOwner onlyWhileOpen whenNotPaused {
        require(newPeriod > 0, "Lock period must be > 0");
        initialLockInPeriodInSeconds = newPeriod;
    }

    function changeVestingInMonths(uint256 newVesting) external onlyOwner onlyWhileOpen whenNotPaused {
        require(newVesting > 0, "Vesting must be > 0");
        vestingMonths = newVesting;
    }

    function changeUsdtToken(IERC20Extented _newUsdt) external onlyOwner onlyWhileOpen whenNotPaused {
        require(_newUsdt.decimals() == 6, "USDT must have 6 decimals");
        usdtToken = _newUsdt;
    }

    function withdrawToken(address _tokenContract, uint256 _amount) external onlyOwner nonReentrant whenNotPaused {
        require(_tokenContract != address(0), "Token address can't be zero");
        IERC20(_tokenContract).safeTransfer(msg.sender, _amount);
        emit WithdrawToken(_tokenContract, msg.sender, _amount);
    }
    
    function withdrawUSDT(address _to, uint256 _amount) external onlyOwner nonReentrant whenNotPaused {
    require(_to != address(0), "Invalid recipient address");
    require(_amount > 0, "Amount must be greater than 0");
    require(usdtToken.balanceOf(address(this)) >= _amount, "Insufficient USDT balance in contract");

    usdtToken.safeTransfer(_to, _amount);
    }

    // function withdrawEther(address payable _to, uint256 _amount) public virtual onlyOwner {
    //     require(_to != address(0), "Invalid address");
    //     require(_amount > 0, "Amount must be > 0");
    //     require(address(this).balance >= _amount, "Insufficient balance");

    //     _to.transfer(_amount);
    // }

    //  Set new tax rates (basis points)
    function setTaxRates(uint256 buyTax) external onlyOwner whenNotPaused {
        require(buyTax <= 10000, "Too high");
        taxOnBuy = buyTax;
        // taxOnSell = sellTax;
        emit TaxSettingsUpdated(buyTax);
    }

    //  Set new donation wallet
    function setDonationWallet(address _wallet) external onlyOwner whenNotPaused {
        require(_wallet != address(0), "Zero address");
        donationWallet = _wallet;
        emit DonationWalletUpdated(_wallet);
    }

    function pause() external onlyOwner {
    _pause();
    }

    function unpause() external onlyOwner {
    _unpause();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
