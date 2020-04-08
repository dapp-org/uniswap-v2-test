pragma solidity 0.5.16;

import {DSTest} from "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";
import {DSMath} from "ds-math/math.sol";
import {UniswapV2Factory} from "uniswap-v2-core/contracts/UniswapV2Factory.sol";
import {UniswapV2Pair} from "uniswap-v2-core/contracts/UniswapV2Pair.sol";
import {UniswapV2Router01} from "uniswap-v2-periphery/contracts/UniswapV2Router01.sol";
import {WETH9} from "uniswap-v2-periphery/contracts/test/WETH9.sol";

contract User {
    UniswapV2Router01 router;
    UniswapV2Pair public pair0; // tokenA, tokenB
    UniswapV2Pair public pair1; // tokenA, weth

    constructor(UniswapV2Router01 _router) public {
        router = _router;
    }

    function() payable external {}

    function init(DSToken tokenA, DSToken tokenB, WETH9 weth) public {
        pair0 = UniswapV2Pair(router.factory().createPair(address(tokenA), address(tokenB)));
        pair1 = UniswapV2Pair(router.factory().createPair(address(tokenA), address(weth)));

        pair0.approve(address(router), uint(-1));
        pair1.approve(address(router), uint(-1));

        tokenA.approve(address(router));
        tokenB.approve(address(router));
    }

    function join(address tokenA, address tokenB, uint amountA, uint amountB) public {
        router.addLiquidity(tokenA, tokenB, amountA, amountB, 0, 0, address(this), uint(-1));
    }

    function exit(address tokenA, address tokenB, uint liquidity) public {
        router.removeLiquidity(tokenA, tokenB, liquidity, 0, 0, address(this), uint(-1));
    }

    function joinETH(address token, uint amount, uint amountETH) public {
        router.addLiquidityETH.value(amountETH)(address(token), amount, 0, 0, address(this), uint(-1));
    }

    function exitETH(address token, uint liquidity) public {
        router.removeLiquidityETH(address(token), liquidity, 0, 0, address(this), uint(-1));
    }


    function swap_exact_0(uint amountIn, uint amountOutMin, address[] memory path) public {
        router.swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), uint(-1));
    }
}

contract RouterTest is DSTest, DSMath {
    UniswapV2Factory  factory;
    WETH9             weth;
    DSToken           tokenA;
    DSToken           tokenB;
    UniswapV2Router01 router;
    User              user;

    function setUp() public {
        factory = new UniswapV2Factory(address(this));
        weth    = new WETH9();
        tokenA  = new DSToken("TST-A");
        tokenB  = new DSToken("TST-B");
        router  = new UniswapV2Router01(address(weth));
        user    = new User(router);

        user.init(tokenA, tokenB, weth);
    }

    // Fund the user
    function giftSome(uint amount) public {
        tokenA.mint(address(user), amount);
        tokenB.mint(address(user), amount);
        address(user).transfer(amount);
    }

    function assert_k_strict(UniswapV2Pair pair) internal {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint totalSupply = pair.totalSupply();
        assertTrue(totalSupply * totalSupply <= uint(reserve0) * uint(reserve1));
        assertTrue((totalSupply + 1) ** 2 > uint(reserve0) * uint(reserve1));
    }

    function assert_k(UniswapV2Pair pair) internal {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint totalSupply = pair.totalSupply();
        assertTrue(totalSupply * totalSupply <= uint(reserve0) * uint(reserve1));
    }

    function assertEqApprox(uint x, uint y, uint error_magnitude) internal {
        if (x >= y) { return assertTrue(wdiv(x, y) - WAD < error_magnitude); }
        else        { return assertTrue(wdiv(y, x) - WAD < error_magnitude); }
    }

    // Sanity check - ensure DAPP_TEST_ADDRESS is uniswap deployer
    function test_factory_address() public {
        assertEq(address(factory), address(router.factory()));
    }

    // Sanity check - should match the hard coded value from UniswapV2Library.pairFor
    function test_factory_codehash() public {
        bytes32 hash = keccak256(type(UniswapV2Pair).creationCode);
        assertEq(hash, hex'9a7290cf45ada5f545b2a5fd34506a296fcb1a6f4ad75e4737d573e5d5511480');
    }

    // Sanity check
    function test_pairs() public {
        assertEq(address(user.pair0()), factory.getPair(address(tokenA), address(tokenB)));
        assertEq(address(user.pair1()), factory.getPair(address(tokenA), address(weth)));
    }

    // Join with tokens
    function test_add_remove_liquidity(uint64 amountA, uint64 amountB, uint64 amountA2, uint64 amountB2) public {
        UniswapV2Pair pair = UniswapV2Pair(factory.getPair(address(tokenA), address(tokenB)));
        uint fromBalance   = 100 ether; giftSome(fromBalance);

        // Behaviour 1: join a new exchange with zero liquidity
        user.join(address(tokenA), address(tokenB), amountA, amountB);
        assert_k_strict(pair);

        // Behaviour 2: join an exchange with existing liquidity
        user.join(address(tokenA), address(tokenB), amountA2, amountB2);
        assert_k(pair);

        // Check depleted user balances == reserves
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(fromBalance - tokenA.balanceOf(address(user)), reserve1);
        assertEq(fromBalance - tokenB.balanceOf(address(user)), reserve0);

        // Check user liquidity plus locked liquidity == total liquidity
        uint liquidity = pair.balanceOf(address(user));
        assertEq(pair.totalSupply(), liquidity + pair.MINIMUM_LIQUIDITY());

        // Remove all liquidiy
        user.exit(address(tokenA), address(tokenB), liquidity);

        // Check liquidity balances
        assertEq(pair.totalSupply(), pair.MINIMUM_LIQUIDITY());
        assertEq(pair.balanceOf(address(user)), 0);

        // Check token balances
        // Tokens remaining at the exchange are no less than locked liquidity
        assertTrue(
          tokenA.balanceOf(address(pair)) * tokenB.balanceOf(address(pair))
          > pair.MINIMUM_LIQUIDITY() ** 2
        );
        assertEqApprox(
          tokenA.balanceOf(address(pair)) * tokenB.balanceOf(address(pair)),
          pair.MINIMUM_LIQUIDITY() ** 2,
          0.05 ether // 0.05% error margin
        );
        // User balances are no less than starting balances less locked liquidity
        assertTrue(
          tokenA.balanceOf(address(user)) + tokenB.balanceOf(address(user))
          > (fromBalance * 2) - (pair.MINIMUM_LIQUIDITY() ** 2)
        );
        assertEqApprox(
          tokenA.balanceOf(address(user)) + tokenB.balanceOf(address(user)),
          (fromBalance * 2) - (pair.MINIMUM_LIQUIDITY() ** 2),
          0.000000000000005 ether // % error margin
        );

        assert_k(pair);
    }


    // Join with token & ETH
    function test_add_remove_liquidity_ETH(uint64 amountA, uint64 amountETH, uint64 amountA2, uint64 amountETH2) public {
        UniswapV2Pair pair = UniswapV2Pair(factory.getPair(address(tokenA), address(weth)));
        uint fromBalance   = 100 ether; giftSome(fromBalance);

        // Behaviour 1: join a new exchange with zero liquidity
        user.joinETH(address(tokenA), amountA, amountETH);
        assert_k_strict(pair);

        // Behaviour 2: join an exchange with existing liquidity
        user.joinETH(address(tokenA), amountA2, amountETH2);
        assert_k(pair);

        // Check depleted user balances == reserves
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(fromBalance - tokenA.balanceOf(address(user)), reserve1);
        assertEq(fromBalance - address(user).balance, reserve0);

        // Check user liquidity plus locked liquidity == total liquidity
        uint liquidity = pair.balanceOf(address(user));
        assertEq(pair.totalSupply(), liquidity + pair.MINIMUM_LIQUIDITY());

        // Remove all liquidiy
        user.exitETH(address(tokenA), liquidity);

        // Check liquidity
        assertEq(pair.totalSupply(), pair.MINIMUM_LIQUIDITY());
        assertEq(pair.balanceOf(address(user)), 0);

        // Check token balances
        // Tokens remaining at the exchange are no less than locked liquidity
        assertTrue(
          tokenA.balanceOf(address(pair)) * weth.balanceOf(address(pair))
          > pair.MINIMUM_LIQUIDITY() ** 2
        );
        assertEqApprox(
          tokenA.balanceOf(address(pair)) * weth.balanceOf(address(pair)),
          pair.MINIMUM_LIQUIDITY() ** 2,
          0.05 ether // 0.05% error margin
        );
        // User balances are no less than starting balances less locked liquidity
        assertTrue(
          tokenA.balanceOf(address(user)) + address(user).balance
          > (fromBalance * 2) - (pair.MINIMUM_LIQUIDITY() ** 2)
        );
        assertEqApprox(
          tokenA.balanceOf(address(user)) + address(user).balance,
          (fromBalance * 2) - (pair.MINIMUM_LIQUIDITY() ** 2),
          0.000000000000005 ether // error margin
        );

        assert_k(pair);
    }

}
