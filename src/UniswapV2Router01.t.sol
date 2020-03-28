pragma solidity 0.5.16;

import {DSTest} from "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";
import {UniswapV2Factory} from "uniswap-v2-core/contracts/UniswapV2Factory.sol";
import {UniswapV2Pair} from "uniswap-v2-core/contracts/UniswapV2Pair.sol";
import {UniswapV2Router01} from "uniswap-v2-periphery/contracts/UniswapV2Router01.sol";
import {WETH9} from "uniswap-v2-periphery/contracts/test/WETH9.sol";

contract RouterTest is DSTest {
    UniswapV2Router01 router;
    UniswapV2Factory  factory;
    UniswapV2Pair     pair;
    WETH9             weth;
    DSToken           tokenA;
    DSToken           tokenB;

    function setUp() public {
        factory = new UniswapV2Factory(address(this));
        weth    = new WETH9();
        router  = new UniswapV2Router01(address(weth));
        tokenA  = new DSToken("TST-A");
        tokenB  = new DSToken("TST-B");
        pair    = UniswapV2Pair(factory.createPair(address(tokenA), address(tokenB)));

        tokenA.approve(address(router));
        tokenB.approve(address(router));
    }

    function giftSome(uint amountA, uint amountB) public {
        tokenA.mint(address(this), amountA);
        tokenB.mint(address(this), amountB);
    }

    function assert_k_strict() internal {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint totalSupply = pair.totalSupply();
        assertTrue(totalSupply * totalSupply <= uint(reserve0) * uint(reserve1));
        assertTrue((totalSupply + 1) ** 2 > uint(reserve0) * uint(reserve1));
    }

    function assert_k() internal {
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

    function test_initial_join() public {
        giftSome(1 ether, 4 ether);
        router.addLiquidity(address(tokenA), address(tokenB), 1 ether, 4 ether, 0, 0, address(this), uint(-1));
        assertEq(pair.balanceOf(address(this)), 2 ether - pair.MINIMUM_LIQUIDITY());
    }

    function test_join_abstract(uint64 initialA, uint64 initialB, uint64 amtA, uint64 amtB) public {
        giftSome(100 ether, 100 ether);

        router.addLiquidity(address(tokenA), address(tokenB), initialA, initialB, 0, 0, address(this), uint(-1));
        assert_k_strict();
        router.addLiquidity(address(tokenA), address(tokenB), amtA, amtB, 0, 0, address(this), uint(-1));
        assert_k();
    }

}
