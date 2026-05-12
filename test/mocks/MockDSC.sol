// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
//mock depo
contract MockDSC {
    bool private immutable i_mintShouldFail;
    bool private immutable i_transferFromShouldFail;

    constructor(bool mintShouldFail, bool transferFromShouldFail) {
        i_mintShouldFail = mintShouldFail;
        i_transferFromShouldFail = transferFromShouldFail;
    }

    function mint(address, uint256) external view returns (bool) {
        return !i_mintShouldFail;
    }

    function transferFrom(address, address, uint256) external view returns (bool) {
        return !i_transferFromShouldFail;
    }

    function burn(uint256) external pure {}
}
