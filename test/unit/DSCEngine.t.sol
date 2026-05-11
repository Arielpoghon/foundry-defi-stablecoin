// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockFailedERC20} from "../mocks/MockFailedERC20.sol";
import {MockDSC} from "../mocks/MockDSC.sol";
import {Test} from "forge-std/Test.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address weth;
    address ethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address wbtc;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    uint256 public constant MAX_MINTABLE_DSC = 10000 ether;
    uint256 public constant LIQUIDATION_COVER_AMOUNT = 1000 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    /////////////////////////
    // Constructor Tests   //
    /////////////////////////

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        address[] memory tokenAddresses = new address[](1);
        address[] memory priceFeedAddresses = new address[](2);
        tokenAddresses[0] = weth;
        priceFeedAddresses[0] = ethUsdPriceFeed;
        priceFeedAddresses[1] = wbtcUsdPriceFeed;

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////
    // Price Tests //
    /////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testGetAccountCollateralValueReturnsZeroForFreshUser() public view {
        assertEq(dsce.getAccountCollateralValue(USER), 0);
    }

    function testGetHealthFactorReturnsMaxForUserWithNoDebt() public {
        vm.prank(USER);
        assertEq(dsce.getHealthFactor(), type(uint256).max);
    }

    /////////////////////////////
    // depositCollateral Tests //
    /////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        randomToken.approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(randomToken)));
        dsce.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfTransferFromFailsOnDeposit() public {
        MockFailedERC20 badToken = new MockFailedERC20("BAD", "BAD");
        MockV3Aggregator priceFeed = new MockV3Aggregator(8, 2000e8);
        address[] memory tokenAddresses = new address[](1);
        address[] memory priceFeedAddresses = new address[](1);
        tokenAddresses[0] = address(badToken);
        priceFeedAddresses[0] = address(priceFeed);
        DSCEngine localEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        badToken.mint(USER, AMOUNT_COLLATERAL);
        badToken.setFailTransferFrom(true);

        vm.startPrank(USER);
        badToken.approve(address(localEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        localEngine.depositCollateral(address(badToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 actualTotalDscMinted, uint256 actualCollateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedCollateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);

        assertEq(actualTotalDscMinted, expectedTotalDscMinted);
        assertEq(actualCollateralValueInUsd, expectedCollateralValueInUsd);
    }

    function testCanDepositCollateralAndEmitEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, true, address(dsce));
        emit DSCEngine.CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ///////////////////
    // mintDsc Tests //
    ///////////////////

    function testRevertsIfMintAmountIsZero() public depositedCollateral {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
    }

    function testRevertsIfMintedDscBreaksHealthFactor() public depositedCollateral {
        uint256 expectedHealthFactor = ((dsce.getUsdValue(weth, AMOUNT_COLLATERAL) / 2) * 1e18) / (MAX_MINTABLE_DSC + 1);
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.mintDsc(MAX_MINTABLE_DSC + 1);
    }

    function testCanMintDsc() public depositedCollateral {
        vm.prank(USER);
        dsce.mintDsc(AMOUNT_TO_MINT);

        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, AMOUNT_TO_MINT);
        assertEq(dsc.balanceOf(USER), AMOUNT_TO_MINT);
    }

    function testRevertsIfMintFails() public {
        MockDSC mockDsc = new MockDSC(true, false);
        address[] memory tokenAddresses = new address[](1);
        address[] memory priceFeedAddresses = new address[](1);
        tokenAddresses[0] = weth;
        priceFeedAddresses[0] = ethUsdPriceFeed;
        DSCEngine localEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(localEngine), AMOUNT_COLLATERAL);
        localEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        localEngine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    /////////////////////////////////////
    // depositCollateralAndMint Tests  //
    /////////////////////////////////////

    function testCanDepositCollateralAndMintDscInOneTx() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, AMOUNT_TO_MINT);
        assertEq(collateralValueInUsd, dsce.getUsdValue(weth, AMOUNT_COLLATERAL));
    }

    ///////////////////
    // burnDsc Tests //
    ///////////////////

    function testRevertsIfBurnAmountIsZero() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        dsce.burnDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        assertEq(dsc.balanceOf(USER), 0);
    }

    function testRevertsIfDscTransferFromFailsDuringBurn() public {
        MockDSC mockDsc = new MockDSC(false, true);
        address[] memory tokenAddresses = new address[](1);
        address[] memory priceFeedAddresses = new address[](1);
        tokenAddresses[0] = weth;
        priceFeedAddresses[0] = ethUsdPriceFeed;
        DSCEngine localEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(localEngine), AMOUNT_COLLATERAL);
        localEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        localEngine.mintDsc(AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        localEngine.burnDsc(AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    ////////////////////////////
    // redeemCollateral Tests //
    ////////////////////////////

    function testRevertsIfRedeemAmountIsZero() public depositedCollateral {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.prank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);

        (, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(collateralValueInUsd, 0);
        assertEq(ERC20Mock(weth).balanceOf(USER), STARTING_ERC20_BALANCE);
    }

    function testRevertsIfRedeemBreaksHealthFactor() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MAX_MINTABLE_DSC);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfTransferFailsDuringRedeem() public {
        MockFailedERC20 badToken = new MockFailedERC20("BAD", "BAD");
        MockV3Aggregator priceFeed = new MockV3Aggregator(8, 2000e8);
        address[] memory tokenAddresses = new address[](1);
        address[] memory priceFeedAddresses = new address[](1);
        tokenAddresses[0] = address(badToken);
        priceFeedAddresses[0] = address(priceFeed);
        DSCEngine localEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        badToken.mint(USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        badToken.approve(address(localEngine), AMOUNT_COLLATERAL);
        localEngine.depositCollateral(address(badToken), AMOUNT_COLLATERAL);
        badToken.setFailTransfer(true);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        localEngine.redeemCollateral(address(badToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ///////////////////////////////////
    // redeemCollateralForDsc Tests  //
    ///////////////////////////////////

    function testCanRedeemCollateralForDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, 0);
    }

    /////////////////////
    // liquidate Tests //
    /////////////////////

    function testRevertsIfLiquidationAmountIsZero() public {
        vm.prank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.liquidate(weth, USER, 0);
    }

    function testRevertsIfHealthFactorIsOk() public depositedCollateralAndMintedDsc {
        vm.prank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, AMOUNT_TO_MINT);
    }

    function testCanLiquidateAUser() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MAX_MINTABLE_DSC);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1800e8);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, LIQUIDATION_COVER_AMOUNT);
        dsc.approve(address(dsce), LIQUIDATION_COVER_AMOUNT);
        dsce.liquidate(weth, USER, LIQUIDATION_COVER_AMOUNT);
        vm.stopPrank();

        vm.prank(USER);
        uint256 userHealthFactor = dsce.getHealthFactor();
        assertGt(userHealthFactor, 9e17);
        assertGt(ERC20Mock(weth).balanceOf(LIQUIDATOR), 0);
    }

    function testRevertsIfLiquidationDoesNotImproveHealthFactor() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MAX_MINTABLE_DSC);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1000e8);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, LIQUIDATION_COVER_AMOUNT);
        dsc.approve(address(dsce), LIQUIDATION_COVER_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        dsce.liquidate(weth, USER, LIQUIDATION_COVER_AMOUNT);
        vm.stopPrank();
    }

    /////////////////////////
    // Invalid Price Tests //
    /////////////////////////

    function testRevertsIfUsdValuePriceIsInvalid() public {
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(0);
        vm.expectRevert(DSCEngine.DSCEngine__InvalidPrice.selector);
        dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
    }

    function testRevertsIfTokenAmountFromUsdPriceIsInvalid() public {
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(0);
        vm.expectRevert(DSCEngine.DSCEngine__InvalidPrice.selector);
        dsce.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT);
    }
}
