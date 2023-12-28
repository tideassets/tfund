// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";

interface IA {
  function foo(address a) external;
  function b() external view returns (address);
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
  IB public b;

  constructor() {
    b = IB(address(new B()));
  }

  function foo(IB b_) external {
    b_.foo(address(this));
  }
}

contract TestInterface is Test {
  function test() public {
    A a = new A();
    B b = new B();
    IA ia = IA(address(a));
    ia.foo(address(b));
    console2.log("b.b", ia.b());
    IB(ia.b()).foo(address(ia));
  }
}
