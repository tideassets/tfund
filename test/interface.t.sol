// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";

interface IA {
  function foo(address a) external;
}

interface IB {
  function foo(address a) external;
}

contract B {
  function foo(address a) external pure {
    console2.log("B.foo", a);
  }
}

contract A {
  function foo(IB b) external {
    b.foo(address(this));
  }
}

contract TestInterface is Test {
  function test() public {
    A a = new A();
    B b = new B();
    IA(address(a)).foo(address(b));
  }
}
