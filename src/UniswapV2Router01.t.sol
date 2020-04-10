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

    function sellTokens(uint qty, DSToken A, DSToken B) public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(A); tokens[1] = address(B);
        router.swapExactTokensForTokens(qty, 0, tokens, address(this), uint(-1));
    }

    function buyTokens(uint qty, DSToken A, DSToken B) public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(A); tokens[1] = address(B);
        router.swapTokensForExactTokens(qty, uint(-1), tokens, address(this), uint(-1));
    }

    function sellETH(uint amountETH) public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(pair1.token0()); tokens[1] = address(pair1.token1());
        router.swapExactETHForTokens.value(amountETH)(0, tokens, address(this), uint(-1));
    }

    function buyETH(uint amountETH) public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(pair1.token1()); tokens[1] = address(pair1.token0());
        router.swapTokensForExactETH(amountETH, uint(-1), tokens, address(this), uint(-1));
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
    function test_pair_getters() public {
        assertEq(address(user.pair0()), factory.getPair(address(tokenA), address(tokenB)));
        assertEq(address(user.pair1()), factory.getPair(address(tokenA), address(weth)));
    }

    // Join with tokens
    function test_add_remove_liquidity(uint32 amountA, uint32 amountB, uint32 amountA2, uint32 amountB2) public {
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
        assertEq(pair.balanceOf(address(user)), 0);
        assertEq(pair.totalSupply(), pair.MINIMUM_LIQUIDITY());
        assertEq(pair.totalSupply(), pair.balanceOf(address(0)));

        // Check token balances
        //
        // The error margin on the exchange balances appears greater because
        // the amount of locked liquidity is relatively small in comparison to
        // the amounts being deposited and widthdrawn.
        //
        // Tokens remaining at the exchange are slightly in excess of the
        // equivalent recorded liquidity balance.
        assertTrue(
          tokenA.balanceOf(address(pair)) * tokenB.balanceOf(address(pair))
          > pair.totalSupply() ** 2
        );
        // Note that this error margin is proportional to the size of amounts
        // being deposited and withdrawn.
        assertEqApprox(
          tokenA.balanceOf(address(pair)) * tokenB.balanceOf(address(pair)),
          pair.totalSupply() ** 2,
          0.06 ether // 0.06% error margin
        );
        // Final user balances ~= starting balances less the intial locked
        // liquidity burned by the exhange.
        assertTrue(
          tokenA.balanceOf(address(user)) + tokenB.balanceOf(address(user))
          > (fromBalance * 2) - (pair.totalSupply() ** 2)
        );
        assertEqApprox(
          tokenA.balanceOf(address(user)) + tokenB.balanceOf(address(user)),
          (fromBalance * 2) - (pair.totalSupply() ** 2),
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

        // Check liquidity balances
        assertEq(pair.balanceOf(address(user)), 0);
        assertEq(pair.totalSupply(), pair.MINIMUM_LIQUIDITY());
        assertEq(pair.totalSupply(), pair.balanceOf(address(0)));

        // Check token balances
        //
        // The error margin on the exchange balances appears greater because
        // the amount of locked liquidity is relatively small in comparison to
        // the amounts being deposited and widthdrawn.
        //
        // Tokens remaining at the exchange are slightly in excess of the
        // equivalent recorded liquidity balance.
        assertTrue(
          tokenA.balanceOf(address(pair)) * weth.balanceOf(address(pair))
          > pair.totalSupply() ** 2
        );
        assertEqApprox(
          tokenA.balanceOf(address(pair)) * weth.balanceOf(address(pair)),
          pair.totalSupply() ** 2,
          0.06 ether // 0.06% error margin
        );
        // Final user balances ~= starting balances less the intial locked
        // liquidity burned by the exhange.
        assertTrue(
          tokenA.balanceOf(address(user)) + address(user).balance
          > (fromBalance * 2) - (pair.totalSupply() ** 2)
        );
        assertEqApprox(
          tokenA.balanceOf(address(user)) + address(user).balance,
          (fromBalance * 2) - (pair.totalSupply() ** 2),
          0.000000000000005 ether // error margin
        );

        assert_k(pair);
    }

    // Fund the user and add liquidity
    function setupSwap(uint amt) public {
        giftSome(amt * 4);
        user.join(address(tokenA), address(tokenB), amt, amt / 3);
        user.join(address(tokenA), address(tokenB), amt, amt / 3);
    }

    function setupSwapETH(uint amt) public {
        giftSome(amt * 4);
        user.joinETH(address(tokenA), amt, amt / 3);
        user.joinETH(address(tokenA), amt, amt / 3);
    }

    // Swap: exact A for B
    function test_swap_exact_A(uint64 amountA) public {
        UniswapV2Pair pair = UniswapV2Pair(factory.getPair(address(tokenA), address(tokenB)));
        setupSwap(amountA);

        // Pre-swap balances
        uint prebalA = tokenA.balanceOf(address(user));
        uint prebalB = tokenB.balanceOf(address(user));
        (uint112 preReserve0, uint112 preReserve1,) = pair.getReserves();

        // Calculate expected amount out
        uint expectedOut = wmul(
          wdiv(amountA, (amountA + uint(preReserve1))),
          uint(preReserve0)
        );

        user.sellTokens(amountA, tokenA, tokenB);

        // Post-swap balances
        (uint112 postReserve0, uint112 postReserve1,) = pair.getReserves();
        uint postbalA = tokenA.balanceOf(address(user));
        uint postbalB = tokenB.balanceOf(address(user));

        // Check changed user balances == change in reserves
        assertEq(prebalA  - postbalA, uint(postReserve1) - uint(preReserve1));
        assertEq(postbalB - prebalB,  uint(preReserve0)  - uint(postReserve0));

        // Check amount received == expected out less the 0.003% fee.
        assertTrue(expectedOut > postbalB - prebalB);
        assertEqApprox(postbalB - prebalB, expectedOut, 0.003 ether);
    }

    // Swap: A for exact B
    function test_swap_exact_B(uint64 amountB) public {
        UniswapV2Pair pair = UniswapV2Pair(factory.getPair(address(tokenA), address(tokenB)));
        setupSwap(amountB);

        // Pre-swap balances
        uint prebalA = tokenA.balanceOf(address(user));
        uint prebalB = tokenB.balanceOf(address(user));
        (uint112 preReserve0, uint112 preReserve1,) = pair.getReserves();

        user.buyTokens(amountB, tokenB, tokenA);

        // Post-swap balances
        (uint112 postReserve0, uint112 postReserve1,) = pair.getReserves();
        uint postbalA = tokenA.balanceOf(address(user));
        uint postbalB = tokenB.balanceOf(address(user));

        // Calculate expected amount in
        uint expectedIn = wmul(
          wdiv(amountB, uint(preReserve1)),
          uint(postReserve0)
        );

        // Check changed user balances == change in reserves
        assertEq(prebalA  - postbalA, uint(postReserve1) - uint(preReserve1));
        assertEq(postbalB - prebalB,  uint(preReserve0)  - uint(postReserve0));

        // Check amount sent == expectedIn plus error margin.
        assertTrue(expectedIn < prebalB - postbalB);
        assertEqApprox(prebalB - postbalB, expectedIn, 0.0016 ether);
    }

    // Swap: exact ETH for A
    function test_swap_send_exact_ETH(uint64 amountETH) public {
        UniswapV2Pair pair = UniswapV2Pair(factory.getPair(address(tokenA), address(weth)));
        setupSwapETH(amountETH);

        // Pre-swap balances
        uint prebalA = tokenA.balanceOf(address(user));
        uint prebalE = address(user).balance;
        (uint112 preReserve0, uint112 preReserve1,) = pair.getReserves();

        // Calculate expected amount out
        uint expectedOut = wmul(
          wdiv(amountETH, (amountETH + uint(preReserve0))),
          uint(preReserve1)
        );

        user.sellETH(amountETH);

        // Post-swap balances
        (uint112 postReserve0, uint112 postReserve1,) = pair.getReserves();
        uint postbalA = tokenA.balanceOf(address(user));
        uint postbalE = address(user).balance;

        // Check changed user balances == change in reserves
        assertEq(prebalA  - postbalA, uint(postReserve1) - uint(preReserve1));
        assertEq(postbalE - prebalE,  uint(preReserve0)  - uint(postReserve0));

        // Check amount received == expected out less the 0.003% fee.
        assertTrue(expectedOut > postbalA - prebalA);
        assertEqApprox(postbalA - prebalA, expectedOut, 0.003 ether);
    }

}
