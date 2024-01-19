const fs = require("fs");
const path = require("path");
const { exec, execSync } = require("child_process");

// 获取命令行参数
const [, , jsonFilePath] = process.argv;

// 读取 JSON 文件
const data = fs.readFileSync(path.resolve(jsonFilePath), "utf8");

// 解析 JSON 数据
const jdata = JSON.parse(data);

// 过滤出所有的 "CREATE" 交易
const createTransactions = jdata.transactions.filter(
  (transaction) => transaction.transactionType === "CREATE"
);

// 将结果格式化为数组
const contracts = createTransactions.map((transaction) => ({
  name: transaction.contractName,
  addr: transaction.contractAddress,
  argv: transaction.arguments,
}));

// 解析 JSON 数据
// const contracts = JSON.parse(data);

// /// 根据类型生成 abi-encode 命令
function generateAbiEncodeCommand(argv) {
  const types = argv
    .map((arg) => {
      if (arg.length === 42) {
        return "address";
      } else if (arg.length > 42) {
        return "bytes";
      } else if (/^\d+$/.test(arg)) {
        return "uint256";
      } else {
        return "string";
      }
    })
    .join(",");

  const values = argv.map((arg) => `${arg}`).join(" ");

  return `"constructor(${types})" ${values}`;
}
// 循环处理每个合约
contracts.forEach((contract) => {
  // 构造命令
  let command = `forge verify-contract --verifier etherscan --verifier-url https://api-sepolia.arbiscan.io/api --watch --etherscan-api-key TK2UEC7AQT91SUIND9YVXMGJFDEQBXQKWR ${contract.addr} ${contract.name} --compiler-version "v0.8.23+commit.f704f362" --chain arbitrum-sepolia`;

  // 如果 argv 不是 null，就添加这个参数
  if (contract.argv !== null) {
    const abiEncodeCommand = generateAbiEncodeCommand(contract.argv);
    command += ` --constructor-args $(cast abi-encode ${abiEncodeCommand})`;
  }

  // 执行命令
  console.log(`${command}`);
  const output = execSync(command);
  console.log(`${output}`);

  execSync("sleep 1");
});
