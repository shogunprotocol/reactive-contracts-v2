// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockToken
 * @dev Simple ERC20 token for testing purposes
 * @notice This token is used for testing the Vault and Strategy contracts
 */
contract MockToken is ERC20 {
    uint8 private _decimals;

    /**
     * @dev Constructor that mints initial supply to the deployer
     * @param name Token name
     * @param symbol Token symbol
     */
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _decimals = 18;
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    /**
     * @dev Mints tokens to a specified address
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @dev Returns the number of decimals
     * @return uint8 Number of decimals
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
