pragma solidity 0.5.15;

import {DSTest} from "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";
import {UniswapV2Exchange} from "contracts/UniswapV2Exchange.sol";
import {UniswapV2Factory} from "contracts/UniswapV2Factory.sol";

contract ExchangeUser {
    UniswapV2Exchange exchange;

    constructor(UniswapV2Exchange _exchange) public {
      exchange = _exchange;
    }

    // Transfer trading tokens to the exchange
    function push(DSToken token, uint amount) public {
      token.push(address(exchange), amount);
    }

    // Transfer liquidity tokens to the exchange
    function push(uint amount) public {
      exchange.transfer(address(exchange), amount);
    }

    function mint() public {
      exchange.mint(address(this));
    }

    function burn() public {
      exchange.burn(address(this));
    }

    function swap(DSToken tokenIn, uint amountOut) public {
      exchange.swap(address(tokenIn), amountOut, address(this));
    }
}

contract Math {
  function sqrt(uint y) public pure returns (uint z) {
    if (y > 3) {
      uint x = y / 2 + 1;
      z = y;
      while (x < z) {
        z = x;
        x = (y / x + x) / 2;
      }
    } else if (y != 0) {
      z = 1;
    }
  }
}

contract ExchangeTest is DSTest, Math {
    UniswapV2Exchange exchange;
    UniswapV2Factory  factory;
    DSToken           token0;
    DSToken           token1;
    ExchangeUser      user;

    function setUp() public {
        token0   = new DSToken("TST-0");
        token1   = new DSToken("TST-1");
        factory  = new UniswapV2Factory(address(this));
        exchange = UniswapV2Exchange(factory.createExchange(address(token0), address(token1)));
        user      = new ExchangeUser(exchange);
    }

    function giftSome() internal {
        token0.mint(address(user), 10 ether);
        token1.mint(address(user), 10 ether);
    }

    // Transfer trading tokens and join
    function addLiquidity(uint amount0, uint amount1) internal {
        user.push(token0, amount0);
        user.push(token1, amount1);
        user.mint();
    }

    // Transfer liquidity tokens and exit
    function removeLiquidity(uint amount) internal {
        user.push(amount);
        user.burn();
    }

    function test_join() public {
        giftSome();
        addLiquidity(10, 40);
        (uint112 reserve0, uint112 reserve1,) = exchange.getReserves();
        assertEq(uint(reserve0), 40);
        assertEq(uint(reserve1), 10);
        assertEq(token0.balanceOf(address(exchange)), 10);
        assertEq(token1.balanceOf(address(exchange)), 40);
        assertEq(exchange.balanceOf(address(user)), 20);
        assertEq(exchange.totalSupply(), 20);
        assertEq(exchange.balanceOf(address(exchange)), 0);
    }

    // the totalSupply should be the geometric mean of the reserves, usually expressed as
    // k = sqrt(x * y). Since we are dealing with integers and not real numbers, it can only
    // be approximated by the integer square root, so we actually check:
    // totalSupply ^ 2  <= x * y < (totalSupply + 1) ^ 2
    function assert_k_invariant_strict() public {
      (uint112 reserve0, uint112 reserve1,) = exchange.getReserves();
      uint totalSupply = exchange.totalSupply();
      assertTrue(totalSupply * totalSupply <= uint(reserve0) * uint(reserve1));
      assertTrue((totalSupply + 1) ** 2 > uint(reserve0) * uint(reserve1));
    }

    function assert_k_at_least() public {
      (uint112 reserve0, uint112 reserve1,) = exchange.getReserves();
      uint totalSupply = exchange.totalSupply();
      assertTrue(totalSupply * totalSupply <= uint(reserve0) * uint(reserve1));
    }

    // testing join with all abstract arguments.
    // runs join twice in order to test both flavors of the liquidity increase
    // in order to get relatively reasonable arguments and not get stuck in a bunch
    // of math overflow, let's start with some modestly sized numbers
    function test_join_abstract(uint64 fstA, uint64 fstB, uint64 sndA, uint64 sndB) public {
      assertEq(exchange.totalSupply(), 0);
      token0.mint(address(user), uint(fstA) + uint(sndA));
      token1.mint(address(user), uint(fstB) + uint(sndB));
      addLiquidity(fstA, fstB);
      assert_k_invariant_strict();
      //the second time is unlikely to be optimal
      addLiquidity(sndA, sndB);
      //after the second round, we don't have k strictly - only optimal joins result in strict k.
      assert_k_at_least();
    }

    // Integer square root (isqrt) satisfies:
    // isqrt(x) ^ 2 <= x < (isqrt(x) + 1) ^ 2
    // However, if y is equal to or larger than
    // sqrt(2^256) = 
    // 340282366920938463463374607431768211455,
    // (y + 1) ** 2 will overflow
    function test_sqrt(uint x) public {
      uint y = sqrt(x);
      assertTrue(y ** 2 <= x);
      if (y >= 340282366920938463463374607431768211455) {
        assertTrue((y + 1) ** 2 < x);
      } else {
        assertTrue(x < (y + 1) ** 2);
      }
    }

    function test_sqrt_square_inv(uint y) public {
      if (y < 340282366920938463463374607431768211455) {
        assertEq(y, sqrt(y ** 2));
      }
    }

    // large test cases that actually cause the if clause
    // of `test_sqrt(uint x)` to trigger are rare.
    // Here are some more concrete tests.
    function test_sqrt_max() public {
      test_sqrt(uint(-1));
      test_sqrt(uint(-2));
      test_sqrt(uint(-10));
      test_sqrt(0);
      test_sqrt(1);
    }


    function test_exit() public {
        giftSome();
        addLiquidity(10, 40);
        assertEq(exchange.balanceOf(address(user)), 20);
        removeLiquidity(20);

        (uint112 reserve0, uint112 reserve1,) = exchange.getReserves();
        assertEq(uint(reserve0), 0);
        assertEq(uint(reserve1), 0);

        assertEq(token0.balanceOf(address(exchange)), 0);
        assertEq(token1.balanceOf(address(exchange)), 0);
        assertEq(exchange.balanceOf(address(user)), 0);
        assertEq(exchange.totalSupply(), 0);
        assertEq(exchange.balanceOf(address(exchange)), 0);
    }

    // token0 in -> token1 out
    function test_swap0() public {
        giftSome();
        addLiquidity(5 ether, 10 ether);
        user.push(token0, 1 ether);
        user.swap(token0, 1662497915624478906);
        assertEq(token0.balanceOf(address(user)), 4 ether);
        assertEq(token1.balanceOf(address(user)), 1662497915624478906);
    }

    // token1 in -> token0 out
    function test_swap1() public {
        giftSome();
        addLiquidity(10 ether, 5 ether);
        user.push(token1, 1 ether);
        user.swap(token1, 453305446940074565);
        assertEq(token1.balanceOf(address(user)), 4 ether);
        assertEq(token0.balanceOf(address(user)), 453305446940074565);
    }
}

contract StubString {
    string public name;
    constructor() public {
        name = "Uniswap V2";
    }
}

contract SubStringTest is DSTest {
    StubString stubstring;
    function setUp() public {
        stubstring = new StubString();
    }

    function test_checkName() public {
        string memory name = stubstring.name();
        bytes32 name32;
        assembly {
            name32 := mload(add(name, 0x20))
        }
        assertEq(name32, "Uniswap V2");
    }
}


