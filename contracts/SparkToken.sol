// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract SandToken is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC20_init("SandToken", "SAND");
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

    
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }

    //  Burn tokens (reduces total supply)
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // Mint tokens (onlyOwner)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // Required for UUPS upgradeability
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}


