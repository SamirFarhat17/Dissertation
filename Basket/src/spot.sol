
pragma solidity >=0.5.12;

import "./lib.sol";

interface VatLike {
    function file(bytes32, bytes32, uint) external;
}

interface PipLike {
    function peek() external returns (bytes32, bool);
}

contract Spotter is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address guy) external note auth { wards[guy] = 1;  }
    function deny(address guy) external note auth { wards[guy] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Spotter/not-authorized");
        _;
    }

    // --- Data ---
    struct Ilk {
        PipLike pip;  // Price Feed
        uint256 mat;  // Liquidation ratio [ray]
    }

    mapping (bytes32 => Ilk) public ilks;

    VatLike public vat;  // CDP Engine
    uint256 public par;  // ref per dai [ray]

    uint256 public live;

    // --- Events ---
    event Poke(
      bytes32 ilk,
      bytes32 val,  // [wad]
      uint256 spot  // [ray]
    );

    // --- Init ---
    constructor(address vat_) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
        par = ONE;
        live = 1;
    }

    // --- Math ---
    uint constant ONE = 10 ** 27;

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, ONE) / y;
    }

    // --- Administration ---
    function file(bytes32 ilk, bytes32 what, address pip_) external note auth {
        require(live == 1, "Spotter/not-live");
        if (what == "pip") ilks[ilk].pip = PipLike(pip_);
        else revert("Spotter/file-unrecognized-param");
    }
    function file(bytes32 what, uint data) external note auth {
        require(live == 1, "Spotter/not-live");
        if (what == "par") par = data;
        else revert("Spotter/file-unrecognized-param");
    }
    function file(bytes32 ilk, bytes32 what, uint data) external note auth {
        require(live == 1, "Spotter/not-live");
        if (what == "mat") ilks[ilk].mat = data;
        else revert("Spotter/file-unrecognized-param");
    }

    // --- Update value ---
    function poke(bytes32 ilk) external {
        (bytes32 val, bool has) = ilks[ilk].pip.peek();
        uint256 spot = has ? rdiv(rdiv(mul(uint(val), 10 ** 9), par), ilks[ilk].mat) : 0;
        vat.file(ilk, "spot", spot);
        emit Poke(ilk, val, spot);
    }

    function cage() external note auth {
        live = 0;
    }
}
