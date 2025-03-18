// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MyDex.sol";
import "../src/RNT.sol";
import "../lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "../lib/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../lib/v2-periphery/contracts/interfaces/IWETH.sol";
import "../lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

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
  MyDex public dex; // DEX 合约
  RNT public token; // 测试代币
  IUniswapV2Factory public factory; // Uniswap V2 工厂合约
  IUniswapV2Router02 public router; // Uniswap V2 路由合约
  IUniswapV2Pair public pair; // Token-WETH 交易对
  IWETH public weth; // WETH 合约

  // 测试用户地址
  address public user1;
  address public user2;
  // 初始流动性配置：1 ETH = 1000 tokens
  uint256 constant INITIAL_ETH = 100 ether;
  uint256 constant INITIAL_TOKENS = 100000 ether;

  /**
   * @notice 在每个测试用例前设置测试环境
   * @dev 部署所有必要的合约并初始化测试状态
   */
  function setUp() public {
    // 1. 部署合约
    user1 = makeAddr("user1");
    user2 = makeAddr("user2");
    factory = IUniswapV2Factory(deployCode("out/UniswapV2Factory.sol/UniswapV2Factory.json", abi.encode(address(this))));
    weth = IWETH(deployCode("out/WETH9.sol/WETH9.json"));
    router = IUniswapV2Router02(deployCode("out/UniswapV2Router02.sol/UniswapV2Router02.json", abi.encode(address(factory), address(weth))));
    dex = new MyDex(address(factory), address(weth));
    token = new RNT(INITIAL_TOKENS * 4);

    // 2. 给用户一些 ETH 和代币
    vm.deal(user1, 1 ether);
    token.transfer(user1, 1000 ether);

    token.transfer(user2, 1000 ether);

    // 3. 添加初始流动性
    token.approve(address(router), INITIAL_TOKENS);
    router.addLiquidityETH{ value: INITIAL_ETH }(address(token), INITIAL_TOKENS, INITIAL_TOKENS, INITIAL_ETH, address(this), block.timestamp);
    pair = IUniswapV2Pair(factory.getPair(address(token), address(weth)));
    require(address(pair) != address(0), "Pair not created");
  }

  /**
   * @notice 测试添加流动性功能
   * @dev 验证用户能否成功添加 ETH 和代币的流动性
   */
  function testAddLiquidity() public {
    vm.startPrank(user1);

    // 记录初始状态
    console.log("=== Initial State ===");
    console.log("User token balance:", token.balanceOf(user1));
    console.log("User ETH balance:", user1.balance);

    // 持与初始流动性相同的比例 (1:1000)
    token.approve(address(router), type(uint256).max);
    uint256 amountETH = 1 ether;
    uint256 amountTokenDesired = 1000 ether;

    // 执行
    router.addLiquidityETH{ value: amountETH }(
      address(token),
      amountTokenDesired,
      amountTokenDesired * 99 / 100, // 最小代币数量（1% 滑点）
      amountETH * 99 / 100, // 最小 ETH 数量（1% 滑点）
      user1,
      block.timestamp
    );


    vm.stopPrank();
  }
  /**
   * @notice 测试使用 ETH 换取代币
   * @dev 验证用户能否使用 ETH 换取代币
   */

  function testSwapExactETHForTokens() public {
    vm.startPrank(user1);

    // 记录初始状态
    console.log("=== Initial State ===");
    console.log("User token balance:", token.balanceOf(user1));
    console.log("User ETH balance:", user1.balance);

    // 执行
    dex.sellETH{ value: 1 ether }(address(token), 987 ether);

    // 验证
    console.log("=== Final State ===");
    console.log("User token balance:", token.balanceOf(user1));
    console.log("User ETH balance:", user1.balance);

    require(token.balanceOf(user1) >= 987 ether, "Token balance not correct");
  }

  /**
   * @notice 测试使用代币换取 ETH
   * @dev 验证用户能否使用代币换取 ETH
   */
  function testSwapExactTokensForETH() public {
    vm.startPrank(user2);

    // 记录初始状态
    console.log("=== Initial State ===");
    console.log("User token balance:", token.balanceOf(user2));
    console.log("User ETH balance:", user2.balance);

    token.approve(address(dex), 1000 ether);
    // 执行
    dex.buyETH(address(token), 1000 ether, 0.9 ether); // 期望至少获得 0.9 ETH（考虑 0.3% 手续费）

    // 验证
    console.log("=== Final State ===");
    console.log("User token balance:", token.balanceOf(user2));
    console.log("User ETH balance:", user2.balance);

    // 验证
    require(user2.balance >= 0.9 ether, "No ETH received");

    vm.stopPrank();
  }
}
