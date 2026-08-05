import Lake
open Lake DSL

package qrcertBlueprint where
  version := v!"0.1.0"

@[default_target]
lean_lib QRCertBlueprint where
  roots := #[`QRCertBlueprint, `QRCertWaveletFingerprint,
    `ReflectionKernel, `RamseyCertificate, `CustodyPolicy, `AgenticPayments]
