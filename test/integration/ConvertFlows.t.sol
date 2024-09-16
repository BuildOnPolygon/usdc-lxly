// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Base, Events} from "../Base.sol";

contract ConvertFlows is Base {
    bytes private _emptyBytes;

    /// @notice Alice converts 1000 L2_WUSDC to L2_USDC for herself, using approve().
    function testConvertsWrappedUsdcToNativeUsdc() public {
        vm.selectFork(_l2Fork);
        vm.startPrank(_alice);

        // setup
        uint256 wrappedBalance1 = _erc20L2Wusdc.balanceOf(_alice);

        uint256 amount = _toUSDC(1000);
        _erc20L2Wusdc.approve(address(_nativeConverter), amount);

        // check that our convert event is emitted
        vm.expectEmit(address(_nativeConverter));
        emit Events.Convert(_alice, _alice, amount);

        // call convert
        _nativeConverter.convert(_alice, amount, _emptyBytes);

        // alice's L2_WUSDC balance decreased
        uint256 wrappedBalance2 = _erc20L2Wusdc.balanceOf(_alice);
        assertEq(wrappedBalance1 - wrappedBalance2, amount);

        // alice's L2_USDC balance increased
        assertEq(_erc20L2Usdc.balanceOf(_alice), amount);

        // converter's L2_BWUSDC balance increased
        assertEq(_erc20L2Wusdc.balanceOf(address(_nativeConverter)), amount);

        _assertUsdcSupplyAndBalancesMatch();
    }

    /// @notice Alice converts 1000 L2_WUSDC to L2_USDC for herself, using permit().
    function testConvertsWithPermit() public {
        vm.selectFork(_l2Fork);
        vm.startPrank(_alice);

        // setup
        uint256 wrappedBalance1 = _erc20L2Wusdc.balanceOf(_alice);

        uint256 amount = _toUSDC(1000);
        bytes memory permitData = _createPermitData(
            _alice,
            address(_nativeConverter),
            _l2Wusdc,
            amount
        );

        // check that our convert event is emitted
        vm.expectEmit(address(_nativeConverter));
        emit Events.Convert(_alice, _alice, amount);

        // call convert
        _nativeConverter.convert(_alice, amount, permitData);

        // alice's L2_WUSDC balance decreased
        uint256 wrappedBalance2 = _erc20L2Wusdc.balanceOf(_alice);
        assertEq(wrappedBalance1 - wrappedBalance2, amount);

        // alice's L2_USDC balance increased
        assertEq(_erc20L2Usdc.balanceOf(_alice), amount);

        // converter's L2_BWUSDC balance increased
        assertEq(_erc20L2Wusdc.balanceOf(address(_nativeConverter)), amount);

        _assertUsdcSupplyAndBalancesMatch();
    }

    /// @notice Alice permits a 500 L2_WUSDC spend but tries to convert 1000 L2_WUSDC.
    function testRevertConvertWithInsufficientPermit() public {
        vm.selectFork(_l2Fork);
        vm.startPrank(_alice);

        // setup
        uint256 wrappedBalance1 = _erc20L2Wusdc.balanceOf(_alice);

        uint256 approveAmount = _toUSDC(500);
        uint256 convertAmount = _toUSDC(1000);
        bytes memory permitData = _createPermitData(
            _alice,
            address(_nativeConverter),
            _l2Wusdc,
            approveAmount
        );

        // call convert
        vm.expectRevert(bytes4(0x03fffc4b)); // NotValidAmount()
        _nativeConverter.convert(_alice, convertAmount, permitData);

        // alice's L2_WUSDC balance didn't change
        uint256 wrappedBalance2 = _erc20L2Wusdc.balanceOf(_alice);
        assertEq(wrappedBalance1, wrappedBalance2);

        // alice's L2_USDC balance didn't change
        assertEq(_erc20L2Usdc.balanceOf(_alice), 0);

        _assertUsdcSupplyAndBalancesMatch();
    }

    /// @notice Alice converts 1000 L2_WUSDC to L2_USDC for Bob.
    function testConvertsWrappedUsdcToNativeUsdcForAnotherAddress() public {
        vm.selectFork(_l2Fork);
        vm.startPrank(_alice);

        // setup
        uint256 wrappedBalance1 = _erc20L2Wusdc.balanceOf(_alice);

        uint256 amount = _toUSDC(1000);
        _erc20L2Wusdc.approve(address(_nativeConverter), amount);

        // check that our convert event is emitted
        vm.expectEmit(address(_nativeConverter));
        emit Events.Convert(_alice, _bob, amount);

        // call convert
        _nativeConverter.convert(_bob, amount, _emptyBytes);

        // alice's L2_WUSDC balance decreased
        uint256 wrappedBalance2 = _erc20L2Wusdc.balanceOf(_alice);
        assertEq(wrappedBalance1 - wrappedBalance2, amount);

        // bob's L2_USDC balance increased
        assertEq(_erc20L2Usdc.balanceOf(_bob), amount);

        // converter's L2_BWUSDC balance increased
        assertEq(_erc20L2Wusdc.balanceOf(address(_nativeConverter)), amount);

        _assertUsdcSupplyAndBalancesMatch();
    }

    /// @notice Alice approves a 500 L2_WUSDC spend but tries to convert 1000 L2_WUSDC.
    function testRevertConvertWithInsufficientApproval() public {
        vm.selectFork(_l2Fork);
        vm.startPrank(_alice);

        // setup
        uint256 wrappedBalance1 = _erc20L2Wusdc.balanceOf(_alice);

        uint256 approveAmount = _toUSDC(500);
        uint256 convertAmount = _toUSDC(1000);
        _erc20L2Wusdc.approve(address(_nativeConverter), approveAmount);

        // call convert
        vm.expectRevert("ERC20: insufficient allowance");
        _nativeConverter.convert(_alice, convertAmount, _emptyBytes);

        // alice's L2_WUSDC balance didn't change
        uint256 wrappedBalance2 = _erc20L2Wusdc.balanceOf(_alice);
        assertEq(wrappedBalance1, wrappedBalance2);

        // alice's L2_USDC balance didn't change
        assertEq(_erc20L2Usdc.balanceOf(_alice), 0);

        _assertUsdcSupplyAndBalancesMatch();
    }

    /// @notice Alice tries to convert 0 L2_WUSDC.
    function testRevertConvertingZero() public {
        vm.selectFork(_l2Fork);
        vm.startPrank(_alice);

        // try to convert 0 L2_WUSDC to L2_USDC
        _erc20L2Wusdc.approve(address(_nativeConverter), 0);
        vm.expectRevert("INVALID_AMOUNT");
        _nativeConverter.convert(_alice, 0, _emptyBytes);

        _assertUsdcSupplyAndBalancesMatch();
    }

    /// @notice Alice tries to convert 1000 L2_WUSDC for address zero.
    function testRevertConvertingForAddressZero() public {
        vm.selectFork(_l2Fork);
        vm.startPrank(_alice);

        // try to convert 1000 L2_WUSDC for address 0
        _erc20L2Wusdc.approve(address(_nativeConverter), _toUSDC(1000));
        vm.expectRevert("INVALID_RECEIVER");
        _nativeConverter.convert(address(0), _toUSDC(1000), _emptyBytes);

        _assertUsdcSupplyAndBalancesMatch();
    }

    function testConverNativeUsdcToWrappedUsdc() public {
        vm.selectFork(_l2Fork);
        vm.startPrank(_alice);

        // setup: alice converts wrapped to native ("seeding" the nativeconverter) and sends to bob
        uint256 amount = _toUSDC(10000);
        _erc20L2Wusdc.approve(address(_nativeConverter), amount);
        _nativeConverter.convert(_bob, amount, _emptyBytes);
        vm.stopPrank();

        // deconvert
        vm.startPrank(_bob);

        // frank has no wrapped
        uint256 wrappedBalance1 = _erc20L2Wusdc.balanceOf(_frank);
        assertEq(wrappedBalance1, 0);

        // bob converts 8k native to wrapped, with frank as the receiver
        uint256 amount2 = _toUSDC(8000);
        _erc20L2Usdc.approve(address(_nativeConverter), amount2);

        // check that our convert event is emitted
        vm.expectEmit(address(_nativeConverter));
        emit Events.Deconvert(_bob, _frank, amount2);

        _nativeConverter.deconvert(_frank, amount2, _emptyBytes);

        // frank has 8k wrapped
        uint256 wrappedBalance2 = _erc20L2Wusdc.balanceOf(_frank);
        assertEq(wrappedBalance2, amount2);

        _assertUsdcSupplyAndBalancesMatch();
    }
}
