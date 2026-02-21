// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Minimal ERC-20 mock simulating the 1UP token in tests.
contract MockERC20 is ERC20 {
    constructor() ERC20("1UP Token", "1UP") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
