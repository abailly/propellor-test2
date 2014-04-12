module Propellor.Property.Dns where

import Propellor
import Propellor.Property.File
import qualified Propellor.Property.Apt as Apt
import qualified Propellor.Property.Service as Service

namedconf :: FilePath
namedconf = "/etc/bind/named.conf.local"

data Zone = Zone
	{ zdomain :: Domain
	, ztype :: Type
	, zfile :: FilePath
	, zmasters :: [IPAddr]
	, zconfiglines :: [String]
	}

zoneDesc :: Zone -> String
zoneDesc z = zdomain z ++ " (" ++ show (ztype z) ++ ")"

type IPAddr = String

type Domain = String

data Type = Master | Secondary
	deriving (Show, Eq)

secondary :: Domain -> [IPAddr] -> Zone
secondary domain masters = Zone
	{ zdomain = domain
	, ztype = Secondary
	, zfile = "db." ++ domain
	, zmasters = masters
	, zconfiglines = ["allow-transfer { }"]
	}

zoneStanza :: Zone -> [Line]
zoneStanza z =
	[ "// automatically generated by propellor"
	, "zone \"" ++ zdomain z ++ "\" {"
	, cfgline "type" (if ztype z == Master then "master" else "slave")
	, cfgline "file" ("\"" ++ zfile z ++ "\"")
	] ++
	(if null (zmasters z) then [] else mastersblock) ++
	(map (\l -> "\t" ++ l ++ ";") (zconfiglines z)) ++
	[ "};"
	, ""
	]
  where
	cfgline f v = "\t" ++ f ++ " " ++ v ++ ";"
	mastersblock =
		[ "\tmasters {" ] ++
		(map (\ip -> "\t\t" ++ ip ++ ";") (zmasters z)) ++
		[ "\t};" ]

-- | Rewrites the whole named.conf.local file to serve the specificed
-- zones.
zones :: [Zone] -> Property
zones zs = hasContent namedconf (concatMap zoneStanza zs)
	`describe` ("dns server for zones: " ++ unwords (map zoneDesc zs))
	`requires` Apt.serviceInstalledRunning "bind9"
	`onChange` Service.reloaded "bind9"