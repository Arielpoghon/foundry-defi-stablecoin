// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
//mock failded
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract MockFailedERC20 is ERC20 {
    bool private s_shouldFailTransfer;
    bool private s_shouldFailTransferFrom;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function setFailTransfer(bool shouldFail) external {
        s_shouldFailTransfer = shouldFail;
    }

    function setFailTransferFrom(bool shouldFail) external {
        s_shouldFailTransferFrom = shouldFail;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        if (s_shouldFailTransfer) {
            return false;
        }
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (s_shouldFailTransferFrom) {
            return false;
        }
        return super.transferFrom(from, to, value);
    }
}
