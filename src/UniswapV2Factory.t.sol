pragma solidity 0.5.16;

import {DSTest} from "ds-test/test.sol";
import {UniswapV2Exchange} from "contracts/UniswapV2Exchange.sol";
import {UniswapV2Factory} from "contracts/UniswapV2Factory.sol";

contract FactoryOwner {
    function setFeeOwner(UniswapV2Factory factory, address owner) public {
        factory.setFeeToSetter(owner);
    }
    function setFeeRecipient(UniswapV2Factory factory, address recipient) public {
        factory.setFeeTo(recipient);
    }
}

contract FactoryTest is DSTest {
    FactoryOwner     owner;
    UniswapV2Factory factory;

    function setUp() public {
        owner   = new FactoryOwner();
        factory = new UniswapV2Factory(address(owner));
    }
}

contract Admin is FactoryTest {
    address who = address(0xdeadbeef);

    function test_initial_fee_owner() public {
        assertEq(factory.feeToSetter(), address(owner));
    }

    function test_update_fee_owner() public {
        assertEq(factory.feeToSetter(), address(owner));
        owner.setFeeOwner(factory, who);
        assertEq(factory.feeToSetter(), who);
    }

    function testFail_update_fee_owner() public {
        factory.setFeeToSetter(who);
    }

    function test_update_fee_recipient() public {
        assertEq(factory.feeTo(), address(0));
        owner.setFeeRecipient(factory, who);
        assertEq(factory.feeTo(), who);
    }

    function testFail_update_fee_recipient() public {
        factory.setFeeTo(who);
    }
}

contract ExchangeFactory is FactoryTest {
    address tokenA = address(0x1);
    address tokenB = address(0x2);
    address tokenC = address(0x3);
    address tokenD = address(0x4);

    function create2address(address token0, address token1) internal view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        bytes32 init = keccak256(type(UniswapV2Exchange).creationCode);
        bytes32 hash = keccak256(abi.encodePacked(hex"ff", factory, salt, init));
        return address(uint160(uint256(hash)));
    }

    function test_create_exchange_0() public {
        address exchange = factory.createExchange(tokenA, tokenB);
        assertEq(exchange, create2address(tokenA, tokenB));
    }

    function test_create_exchange_1() public {
        address exchange = factory.createExchange(tokenC, tokenD);
        assertEq(exchange, create2address(tokenC, tokenD));
    }

    function test_create_exchange_1_sort() public {
      address exchange = factory.createExchange(tokenD, tokenC);
      assertEq(exchange, create2address(tokenC, tokenD));
    }

    function testFail_create_exchange_same_address() public {
        factory.createExchange(tokenA, tokenA);
    }

    function testFail_create_exchange_zero_address() public {
        factory.createExchange(tokenA, address(0));
    }

    function testFail_create_existing_exchange() public {
        factory.createExchange(tokenA, tokenB);
        factory.createExchange(tokenB, tokenA);
    }

    function test_exchanges_count() public {
        factory.createExchange(tokenA, tokenB);
        factory.createExchange(tokenC, tokenD);
        factory.createExchange(tokenA, tokenC);
        factory.createExchange(tokenB, tokenD);
        assertEq(factory.allExchangesLength(), 4);
    }

    function test_find_exchange_by_token_address() public {
        address exchange = factory.createExchange(tokenA, tokenB);
        assertEq(factory.getExchange(tokenA, tokenB), exchange);
        assertEq(factory.getExchange(tokenB, tokenA), exchange);
    }
}
