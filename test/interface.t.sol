// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";

interface IA {
  function foo(address a) external;
  function b() external view returns (address);
  function s() external view returns (uint a, address b);
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
  struct S {
    address a;
    IB b;
    address c;
  }

  IB public b;
  S public s;

  constructor() {
    b = IB(address(new B()));
    s.b = b;
    s.a = address(this);
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
    (uint a_, address b_) = ia.s();
    console2.log("a.b", ia.b(), b_, a_);
    IB(ia.b()).foo(address(ia));
  }
}
