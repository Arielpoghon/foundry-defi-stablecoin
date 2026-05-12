// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
//mocks
contract MockV3Aggregator {
    uint8 public immutable decimals;
    int256 private s_answer;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        s_answer = _initialAnswer;
    }

    function updateAnswer(int256 _answer) external {
        s_answer = _answer;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, s_answer, block.timestamp, block.timestamp, 0);
    }
}
