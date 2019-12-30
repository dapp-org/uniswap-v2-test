pragma solidity 0.5.15;

import {DSTest} from "ds-test/test.sol";
import {UniswapV2} from "contracts/UniswapV2.sol";
import {UniswapV2Factory} from "contracts/UniswapV2Factory.sol";

contract FactoryOwner {
    function setFactoryOwner(UniswapV2Factory factory, address owner) public {
        factory.setFactoryOwner(owner);
    }
    function setFeeRecipient(UniswapV2Factory factory, address recipient) public {
        factory.setFeeRecipient(recipient);
    }
}

contract FactoryTest is DSTest {
    FactoryOwner     owner;
    UniswapV2Factory factory;

    function setUp() public {
        owner   = new FactoryOwner();
        factory = new UniswapV2Factory(type(UniswapV2).creationCode, address(owner));
    }
}

contract Admin is FactoryTest {
    address who = address(0xdeadbeef);

    function test_initial_factory_owner() public {
        assertEq(factory.factoryOwner(), address(owner));
    }

    function test_update_factory_owner() public {
        assertEq(factory.factoryOwner(), address(owner));
        owner.setFactoryOwner(factory, who);
        assertEq(factory.factoryOwner(), who);
    }

    function testFail_update_factory_owner() public {
        factory.setFactoryOwner(who);
    }

    function test_update_fee_recipient() public {
        assertEq(factory.feeRecipient(), address(0));
        owner.setFeeRecipient(factory, who);
        assertEq(factory.feeRecipient(), who);
    }

    function testFail_update_fee_recipient() public {
        factory.setFeeRecipient(who);
    }
}

contract ExchangeFactory is FactoryTest {
    address tokenA = address(0x1);
    address tokenB = address(0x2);
    address tokenC = address(0x3);
    address tokenD = address(0x4);

    function create2address(address token0, address token1) internal view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        bytes32 init = keccak256(type(UniswapV2).creationCode);
        bytes32 hash = keccak256(abi.encodePacked(hex"ff", factory, salt, init));
        return address(uint160(uint256(hash)));
    }

    function test_exchange_bytecode() public {
        assertEq0(factory.exchangeBytecode(), type(UniswapV2).creationCode);
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
        assertEq(factory.exchangesCount(), 4);
    }

    function test_find_exchange_by_token_address() public {
        address exchange = factory.createExchange(tokenA, tokenB);
        assertEq(factory.getExchange(tokenA, tokenB), exchange);
        assertEq(factory.getExchange(tokenB, tokenA), exchange);
    }

    function test_find_tokens_by_exchange_address() public {
        address exchange = factory.createExchange(tokenC, tokenD);
        (address token0, address token1) = factory.getTokens(exchange);
        assertEq(token0, tokenC);
        assertEq(token1, tokenD);
    }
}
