module Propellor.Property.HostingProvider.Linode where

import Propellor
import qualified Propellor.Property.Grub as Grub

-- | Linode's pv-grub-x86_64 does not currently support booting recent
-- Debian kernels compressed with xz. This sets up pv-grub chaing to enable
-- it.
chainPVGrub :: Grub.TimeoutSecs -> Property
chainPVGrub = Grub.chainPVGrub "hd0" "xen/xvda"
