pragma solidity 0.5.15;

import {DSTest} from "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";
import {UniswapV2} from "contracts/UniswapV2.sol";
import {UniswapV2Factory} from "contracts/UniswapV2Factory.sol";

contract ExchangeUser {
    UniswapV2 exchange;

    constructor(UniswapV2 _exchange) public {
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

contract ExchangeTest is DSTest {
    UniswapV2        exchange;
    UniswapV2Factory factory;
    DSToken          token0;
    DSToken          token1;
    ExchangeUser     user;

    function setUp() public {
        token0   = new DSToken("TST-0");
        token1   = new DSToken("TST-1");
        factory  = new UniswapV2Factory(address(this));
        exchange = UniswapV2(factory.createExchange(address(token0), address(token1)));
        user      = new ExchangeUser(exchange);
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
        addLiquidity(10, 40);

        (uint112 reserve0, uint112 reserve1, uint32 _) = exchange.getReserves();
        assertEq(uint(reserve0), 40);
        assertEq(uint(reserve1), 10);

        assertEq(token0.balanceOf(address(exchange)), 10);
        assertEq(token1.balanceOf(address(exchange)), 40);
        assertEq(exchange.balanceOf(address(user)), 20);
        assertEq(exchange.totalSupply(), 20);
        assertEq(exchange.balanceOf(address(exchange)), 0);
    }

    function test_exit() public {
        addLiquidity(10, 40);
        assertEq(exchange.balanceOf(address(user)), 20);
        removeLiquidity(20);

        (uint112 reserve0, uint112 reserve1, uint32 _) = exchange.getReserves();
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
        addLiquidity(5 ether, 10 ether);
        user.push(token0, 1 ether);
        user.swap(token0, 1662497915624478906);
        assertEq(token0.balanceOf(address(user)), 4 ether);
        assertEq(token1.balanceOf(address(user)), 1662497915624478906);
    }

    // token1 in -> token0 out
    function test_swap1() public {
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
