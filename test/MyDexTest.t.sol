// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/MyDex.sol";
import "../src/RNT.sol";
import "../src/interfaces/IUniswapV2Pair.sol";
import "../src/interfaces/IUniswapV2Router02.sol";
import "../src/interfaces/IUniswapV2Factory.sol";
import "../src/interfaces/IWETH.sol";

/**
 * @title MyDex 合约的测试套件
 * @author 0xZ
 * @dev 测试 MyDex 与 Uniswap V2 的所有交互功能，包括添加/移除流动性和代币交换
 * @notice 测试 MyDex 与 Uniswap V2 的交互功能
 * @dev INIT_CODE_PAIR_HASH 问题说明：
 *      1. UniswapV2Factory 合约中计算了 pair 合约的 INIT_CODE_PAIR_HASH
 *         - 这个哈希值是 pair 合约创建时的初始化代码的 keccak256 哈希
 *         - 用于确定新创建的交易对合约地址
 * 
 *      2. UniswapV2Library 中也硬编码了这个哈希值
 *         - 用于计算交易对地址 (pairFor 函数)
 *         - 必须与 Factory 中的值保持一致
 * 
 *      3. 如果两边的哈希值不一致：
 *         - Router 会在错误的地址上查找交易对
 *         - 导致添加流动性等操作失败
 * 
 *      4. 解决方案：
 *         - 更新 lib/v2-core/contracts/UniswapV2Factory.sol 找到第9行添加 bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(UniswapV2Pair).creationCode));
 *         - 运行测试获取 Factory 的 INIT_CODE_PAIR_HASH
 *         - 更新 lib/v2-periphery/contracts/libraries/UniswapV2Library.sol 找到第24行中的哈希值替换 INIT_CODE_PAIR_HASH
 */
contract MyDexTest is Test {
    /// @dev DEX 相关合约实例
    MyDex public dex;                      // 主要测试合约
    RNT public token;                      // ERC20 测试代币
    IUniswapV2Factory public factory;      // UniswapV2 工厂合约
    IUniswapV2Router02 public router;      // UniswapV2 路由合约
    IUniswapV2Pair public pair;           // Token-WETH 交易对
    IWETH public weth;                     // WETH 合约
    
    /// @dev 测试配置常量
    address public user;                   // 测试用户地址
    uint256 constant INITIAL_ETH_LIQUIDITY = 100 ether;
    uint256 constant INITIAL_TOKEN_LIQUIDITY = 1000000 * 10**18;
    
    /**
     * @notice 在每个测试用例前设置测试环境
     * @dev 部署所有必要的合约并初始化测试状态
     */
    function setUp() public {
        console.log("Starting setUp...");
        
        // 部署基础设施
        user = makeAddr("user");
        factory = IUniswapV2Factory(deployCode(
            "out/UniswapV2Factory.sol/UniswapV2Factory.json",
            abi.encode(address(this))
        ));
        console.log("Factory deployed at:", address(factory));

        // 获取并打印 INIT_CODE_PAIR_HASH
        // 这个值需要复制到 UniswapV2Library.sol 中
        bytes32 initCodePairHash = factory.INIT_CODE_PAIR_HASH();
        console.log("initCodePairHash: 0x%x", uint256(initCodePairHash));

        // 部署其他合约
        weth = IWETH(deployCode("out/WETH9.sol/WETH9.json"));
        console.log("WETH deployed at:", address(weth));
        
        router = IUniswapV2Router02(deployCode(
            "out/UniswapV2Router02.sol/UniswapV2Router02.json",
            abi.encode(address(factory), address(weth))
        ));
        console.log("Router deployed at:", address(router));
        
        // 部署和初始化业务合约
        dex = new MyDex(address(factory), address(router));
        console.log("MyDex deployed at:", address(dex));
        
        token = new RNT(INITIAL_TOKEN_LIQUIDITY);
        console.log("Token deployed at:", address(token));

        // 设置测试账户初始状态
        vm.deal(user, 1000 ether);
        token.transfer(user, INITIAL_TOKEN_LIQUIDITY);

        // 创建交易对
        address pairAddress = factory.createPair(address(token), address(weth));
        pair = IUniswapV2Pair(pairAddress);
        console.log("Pair created at:", address(pair));
    }
    
    /**
     * @notice 测试添加流动性功能
     * @dev 验证用户能否成功添加 ETH 和代币的流动性
     */
    function testAddLiquidity() public {
        vm.startPrank(user);
        
        // 记录初始状态
        console.log("=== Initial State ===");
        console.log("User token balance:", token.balanceOf(user));
        console.log("User ETH balance:", user.balance);

        // 设置
        token.approve(address(router), type(uint256).max);
        uint amountTokenDesired = 900 ether;
        uint amountETH = 1 ether;

        // 执行
        try router.addLiquidityETH{value: amountETH}(
            address(token),
            amountTokenDesired,
            amountTokenDesired * 99 / 100,  // 最小代币数量（1% 滑点）
            amountETH * 99 / 100,          // 最小 ETH 数量（1% 滑点）
            user,
            block.timestamp + 120          // 2分钟过期时间
        ) {
            console.log("Liquidity added successfully");
        } catch Error(string memory reason) {
            console.log("Failed with reason:", reason);
            revert(reason);
        } catch {
            console.log("Failed without reason");
            revert("Unknown revert");
        }

        // 验证
        console.log("=== Final State ===");
        console.log("User token balance:", token.balanceOf(user));
        console.log("User ETH balance:", user.balance);
        console.log("LP token balance:", pair.balanceOf(user));

        require(pair.balanceOf(user) > 0, "No LP tokens received");
        vm.stopPrank();
    }

    /**
     * @notice 测试 ETH 换取代币功能
     * @dev 验证用户能否使用 ETH 购买代币
     */
    function testSwapExactETHForTokens() public {
        vm.startPrank(user);
        
        // 准备：添加初始流动性
        _addInitialLiquidity();

        // 记录初始状态
        uint256 userInitialETH = user.balance;
        uint256 userInitialToken = token.balanceOf(user);
        
        // 执行交换
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token);

        router.swapExactETHForTokens{value: 1 ether}(
            0,  // 最小获得代币数量
            path,
            user,
            block.timestamp + 120
        );

        // 验证结果
        assertGt(token.balanceOf(user), userInitialToken, "Token balance should increase");
        assertLt(user.balance, userInitialETH, "ETH balance should decrease");
        vm.stopPrank();
    }

    /**
     * @notice 测试使用代币换取 ETH
     * @dev 验证用户能否使用代币换取 ETH
     */
    function testSwapExactTokensForETH() public {
        vm.startPrank(user);
        
        // 先添加流动性
        token.approve(address(router), type(uint256).max);
        router.addLiquidityETH{value: 10 ether}(
            address(token),
            9000 ether,
            8900 ether,
            9.9 ether,
            user,
            block.timestamp + 120
        );

        // 记录交换前的余额
        uint256 userInitialETH = user.balance;
        uint256 userInitialToken = token.balanceOf(user);
        uint256 swapAmount = 100 ether;

        // 设置交换路径：Token -> WETH
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = address(weth);

        // 执行交换
        token.approve(address(router), swapAmount);
        router.swapExactTokensForETH(
            swapAmount,
            0,  // 接受任何数量的 ETH 输出
            path,
            user,
            block.timestamp + 120
        );

        // 验证余额变化
        assertLt(token.balanceOf(user), userInitialToken, "Token balance should decrease");
        assertGt(user.balance, userInitialETH, "ETH balance should increase");
        vm.stopPrank();
    }

    /**
     * @notice 测试移除流动性功能
     * @dev 验证用户能否成功移除流动性
     */
    function testRemoveLiquidity() public {
        vm.startPrank(user);
        
        // 先添加流动性
        token.approve(address(router), type(uint256).max);
        (,, uint256 liquidity) = router.addLiquidityETH{value: 10 ether}(
            address(token),
            9000 ether,
            8900 ether,
            9.9 ether,
            user,
            block.timestamp + 120
        );

        // 记录初始状态
        uint256 userInitialETH = user.balance;
        uint256 userInitialToken = token.balanceOf(user);
        uint256 lpBalance = pair.balanceOf(user);

        // 移除一半流动性
        pair.approve(address(router), liquidity);
        router.removeLiquidityETH(
            address(token),
            liquidity / 2,
            0,  // 接受任何数量的代币
            0,  // 接受任何数量的 ETH
            user,
            block.timestamp + 120
        );

        // 验证余额变化
        assertGt(token.balanceOf(user), userInitialToken, "Token balance should increase");
        assertGt(user.balance, userInitialETH, "ETH balance should increase");
        assertEq(pair.balanceOf(user), lpBalance / 2, "Should have half LP tokens left");
        vm.stopPrank();
    }

    /**
     * @notice 测试添加超额流动性时的失败情况
     * @dev 验证路由合约能否正确处理添加超额流动性的情况
     */
    function test_RevertWhen_AddLiquidityWithInsufficientTokenAmount() public {
        vm.startPrank(user);
        token.approve(address(router), type(uint256).max);
        
        // 尝试添加超过用户余额的代币数量
        uint256 tooMuchToken = token.balanceOf(user) + 1 ether;
        
        vm.expectRevert();  // 预期交易会失败
        router.addLiquidityETH{value: 1 ether}(
            address(token),
            tooMuchToken,
            tooMuchToken,
            0.99 ether,
            user,
            block.timestamp + 120
        );
        vm.stopPrank();
    }

    /**
     * @notice 测试在没有流动性的情况下交换的失败情况
     * @dev 验证路由合约能否正确处理没有流动性的情况
     */
    function test_RevertWhen_SwapWithInsufficientLiquidity() public {
        vm.startPrank(user);
        
        // 设置交换路径
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token);

        // 尝试在没有流动性的情况下交换
        vm.expectRevert();  // 预期交易会失败
        router.swapExactETHForTokens{value: 1 ether}(
            1 ether,
            path,
            user,
            block.timestamp + 120
        );
        vm.stopPrank();
    }

    /**
     * @notice 测试获取交换输出金额
     * @dev 验证路由合约能否正确计算代币兑换路径的输出金额
     */
    function testGetAmountsOut() public {
        vm.startPrank(user);
        
        // 先添加流动性
        token.approve(address(router), type(uint256).max);
        router.addLiquidityETH{value: 10 ether}(
            address(token),
            9000 ether,
            8900 ether,
            9.9 ether,
            user,
            block.timestamp + 120
        );

        // 设置查询路径
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token);

        // 获取并验证输出金额
        uint256[] memory amounts = router.getAmountsOut(1 ether, path);
        assertEq(amounts.length, 2, "Should return amounts for both tokens");
        assertGt(amounts[1], 0, "Output amount should be greater than 0");
        vm.stopPrank();
    }

    /**
     * @dev 添加初始流动性的辅助函数
     * @return liquidity 添加的流动性数量
     */
    function _addInitialLiquidity() internal returns (uint256 liquidity) {
        token.approve(address(router), type(uint256).max);
        (,, liquidity) = router.addLiquidityETH{value: 10 ether}(
            address(token),
            9000 ether,
            8900 ether,
            9.9 ether,
            user,
            block.timestamp + 120
        );
    }

    /// @dev 允许合约接收 ETH
    receive() external payable {}
}