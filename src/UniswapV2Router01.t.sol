pragma solidity 0.5.16;

import {DSTest} from "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";
import {UniswapV2Factory} from "uniswap-v2-core/contracts/UniswapV2Factory.sol";
import {UniswapV2Pair} from "uniswap-v2-core/contracts/UniswapV2Pair.sol";
import {UniswapV2Router01} from "uniswap-v2-periphery/contracts/UniswapV2Router01.sol";
import {WETH9} from "uniswap-v2-periphery/contracts/test/WETH9.sol";

contract User {
    UniswapV2Router01 router;
    UniswapV2Pair pair0; // tokenA, tokenB
    UniswapV2Pair pair1; // tokenA, weth

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
}

contract RouterTest is DSTest {
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

    // Sanity check - ensure DAPP_TEST_ADDRESS is uniswap deployer
    function test_factory_address() public {
        assertEq(address(factory), address(router.factory()));
    }

    // Sanity check - should match the hard coded value from UniswapV2Library.pairFor
    function test_factory_codehash() public {
        bytes32 hash = keccak256(type(UniswapV2Pair).creationCode);
        assertEq(hash, hex'0da5869adce6550ad0f45d4bf232c2b1d74f62aa7c530e0059956614df93090d');
    }

    function test_add_remove_liquidity(uint64 fstA, uint64 fstB, uint64 sndA, uint64 sndB) public {
        UniswapV2Pair pair = UniswapV2Pair(factory.getPair(address(tokenA), address(tokenB)));
        giftSome(100 ether);

        // Behaviour 1: join a new exchange with zero liquidity
        user.join(address(tokenA), address(tokenB), fstA, fstB);
        assert_k_strict(pair);

        // Behaviour 2: join an exchange with existing liquidity
        user.join(address(tokenA), address(tokenB), sndA, sndB);
        assert_k(pair);

        // Depleted user balances == reserves
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(100 ether - tokenA.balanceOf(address(user)), reserve1);
        assertEq(100 ether - tokenB.balanceOf(address(user)), reserve0);

        // User liquidity plus locked liquidity == total liquidity
        uint liquidity = pair.balanceOf(address(user));
        assertEq(pair.totalSupply(), liquidity + pair.MINIMUM_LIQUIDITY());

        user.exit(address(tokenA), address(tokenB), liquidity);

        assertEq(pair.totalSupply(), pair.MINIMUM_LIQUIDITY());
        assertEq(pair.balanceOf(address(user)), 0);
        assert_k(pair);
    }

    function test_add_remove_liquidity_ETH(uint64 fstA, uint64 fstETH, uint64 sndA, uint64 sndETH) public {
        UniswapV2Pair pair = UniswapV2Pair(factory.getPair(address(tokenA), address(weth)));
        giftSome(100 ether);

        // Behaviour 1: join a new exchange with zero liquidity
        user.joinETH(address(tokenA), fstA, fstETH);
        assert_k_strict(pair);

        // Behaviour 2: join an exchange with existing liquidity
        user.joinETH(address(tokenA), sndA, sndETH);
        assert_k(pair);

        // Depleted user balances == reserves
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(100 ether - tokenA.balanceOf(address(user)), reserve1);
        assertEq(100 ether - address(user).balance, reserve0);

        // User liquidity plus locked liquidity == total liquidity
        uint liquidity = pair.balanceOf(address(user));
        assertEq(pair.totalSupply(), liquidity + pair.MINIMUM_LIQUIDITY());

        user.exitETH(address(tokenA), liquidity);

        assertEq(pair.totalSupply(), pair.MINIMUM_LIQUIDITY());
        assertEq(pair.balanceOf(address(user)), 0);
        assert_k(pair);
    }

}
