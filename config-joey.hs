-- |  This is the live config file used by propellor's author.

import Propellor
import Propellor.CmdLine
import Propellor.Property.Scheduled
import qualified Propellor.Property.File as File
import qualified Propellor.Property.Apt as Apt
import qualified Propellor.Property.Network as Network
import qualified Propellor.Property.Ssh as Ssh
import qualified Propellor.Property.Cron as Cron
import qualified Propellor.Property.Sudo as Sudo
import qualified Propellor.Property.User as User
import qualified Propellor.Property.Hostname as Hostname
--import qualified Propellor.Property.Reboot as Reboot
import qualified Propellor.Property.Tor as Tor
import qualified Propellor.Property.Dns as Dns
import qualified Propellor.Property.OpenId as OpenId
import qualified Propellor.Property.Docker as Docker
import qualified Propellor.Property.Git as Git
import qualified Propellor.Property.SiteSpecific.GitHome as GitHome
import qualified Propellor.Property.SiteSpecific.GitAnnexBuilder as GitAnnexBuilder
import qualified Propellor.Property.SiteSpecific.JoeySites as JoeySites

hosts :: [Host]
hosts =
	-- My laptop
	[ host "darkstar.kitenet.net"
		& Docker.configured
		& Apt.buildDep ["git-annex"] `period` Daily

	-- Nothing super-important lives here.
	, standardSystem "clam.kitenet.net" Unstable
		& cleanCloudAtCost
		& Apt.unattendedUpgrades
		& Network.ipv6to4
		& Tor.isBridge
		& Docker.configured
		& cname "shell.olduse.net"
		& JoeySites.oldUseNetShellBox

		& cname "openid.kitenet.net"
		& Docker.docked hosts "openid-provider"
		 	`requires` Apt.installed ["ntp"]

		& cname "ancient.kitenet.net"
		& Docker.docked hosts "ancient-kitenet"

		& Docker.garbageCollected `period` Daily
		& Apt.installed ["git-annex", "mtr", "screen"]
	
	-- Orca is the main git-annex build box.
	, standardSystem "orca.kitenet.net" Unstable
		& Hostname.sane
		& Apt.unattendedUpgrades
		& Docker.configured
		& Docker.docked hosts "amd64-git-annex-builder"
		& Docker.docked hosts "i386-git-annex-builder"
		! Docker.docked hosts "armel-git-annex-builder-companion"
		! Docker.docked hosts "armel-git-annex-builder"
		& Docker.garbageCollected `period` Daily
		& Apt.buildDep ["git-annex"] `period` Daily
	
	-- Important stuff that needs not too much memory or CPU.
  	, standardSystem "diatom.kitenet.net" Stable
		& Hostname.sane
		& Apt.unattendedUpgrades
		& Apt.serviceInstalledRunning "ntp"
		& Dns.zones myDnsSecondary
		& Apt.serviceInstalledRunning "apache2"
		& Apt.installed ["git", "git-annex", "rsync"]
		& Apt.buildDep ["git-annex"] `period` Daily
		& Git.daemonRunning "/srv/git"
		& File.ownerGroup "/srv/git" "joey" "joey"
		-- git repos restore (how?) (also make backups!)
		-- family annex needs family members to have accounts,
		--     ssh host key etc.. finesse?
		--   (also should upgrade git-annex-shell for it..)
		-- kgb installation and setup
		-- ssh keys for branchable and github repo hooks
		-- gitweb
		-- downloads.kitenet.net setup (including ssh key to turtle)

  --'                        __|II|      ,.
----                      __|II|II|__   (  \_,/\
-----'\o/-'-.-'-.-'-.- __|II|II|II|II|___/   __/ -'-.-'-.-'-.-'-.-'-
--------------------- |      [Docker]       / ----------------------
--------------------- :                    / -----------------------
---------------------- \____, o          ,' ------------------------
----------------------- '--,___________,'  -------------------------

	-- Simple web server, publishing the outside host's /var/www
	, standardContainer "webserver" Stable "amd64"
		& Docker.publish "8080:80"
		& Docker.volume "/var/www:/var/www"
		& Apt.serviceInstalledRunning "apache2"

	-- My own openid provider. Uses php, so containerized for security
	-- and administrative sanity.
	, standardContainer "openid-provider" Stable "amd64"
		& Docker.publish "8081:80"
		& OpenId.providerFor ["joey", "liw"]
			"openid.kitenet.net:8081"
	
	, standardContainer "ancient-kitenet" Stable "amd64"
		& Docker.publish "1994:80"
		& Apt.serviceInstalledRunning "apache2"
		& Apt.installed ["git"]
		& scriptProperty 
			[ "cd /var/"
			, "rm -rf www"
			, "git clone git://git.kitenet.net/kitewiki www"
			, "cd www"
			, "git checkout remotes/origin/old-kitenet.net"
			] `flagFile` "/var/www/blastfromthepast.html"
	
	-- git-annex autobuilder containers
	, gitAnnexBuilder "amd64" 15
	, gitAnnexBuilder "i386" 45
	-- armel builder has a companion container that run amd64 and
	-- runs the build first to get TH splices. They share a home
	-- directory, and need to have the same versions of all haskell
	-- libraries installed.
	, Docker.container "armel-git-annex-builder-companion"
		(image $ System (Debian Unstable) "amd64")
		& Docker.volume GitAnnexBuilder.homedir
		& Apt.unattendedUpgrades
	, Docker.container "armel-git-annex-builder"
		(image $ System (Debian Unstable) "armel")
		& Docker.link "armel-git-annex-builder-companion" "companion"
		& Docker.volumes_from "armel-git-annex-builder-companion"
--		& GitAnnexBuilder.builder "armel" "15 * * * *" True
		& Apt.unattendedUpgrades
	]

gitAnnexBuilder :: Architecture -> Int -> Host
gitAnnexBuilder arch buildminute = Docker.container (arch ++ "-git-annex-builder")
	(image $ System (Debian Unstable) arch)
	& GitAnnexBuilder.builder arch (show buildminute ++ " * * * *") True
	& Apt.unattendedUpgrades

-- This is my standard system setup.
standardSystem :: HostName -> DebianSuite -> Host
standardSystem hn suite = host hn
	& Apt.stdSourcesList suite `onChange` Apt.upgrade
	& Apt.installed ["etckeeper"]
	& Apt.installed ["ssh"]
	& GitHome.installedFor "root"
	& User.hasSomePassword "root"
	-- Harden the system, but only once root's authorized_keys
	-- is safely in place.
	& check (Ssh.hasAuthorizedKeys "root")
		(Ssh.passwordAuthentication False)
	& User.accountFor "joey"
	& User.hasSomePassword "joey"
	& Sudo.enabledFor "joey"
	& GitHome.installedFor "joey"
	& Apt.installed ["vim", "screen", "less"]
	& Cron.runPropellor "30 * * * *"
	-- I use postfix, or no MTA.
	& Apt.removed ["exim4", "exim4-daemon-light", "exim4-config", "exim4-base"]
		`onChange` Apt.autoRemove

-- This is my standard container setup, featuring automatic upgrades.
standardContainer :: Docker.ContainerName -> DebianSuite -> Architecture -> Host
standardContainer name suite arch = Docker.container name (image system)
	& Apt.stdSourcesList suite
	& Apt.unattendedUpgrades
  where
	system = System (Debian suite) arch

-- | Docker images I prefer to use.
image :: System -> Docker.Image
image (System (Debian Unstable) arch) = "joeyh/debian-unstable-" ++ arch
image (System (Debian Stable) arch) = "joeyh/debian-stable-" ++ arch
image _ = "debian-stable-official" -- does not currently exist!

-- Clean up a system as installed by cloudatcost.com
cleanCloudAtCost :: Property
cleanCloudAtCost = propertyList "cloudatcost cleanup"
	[ Hostname.sane
	, Ssh.uniqueHostKeys
	, "worked around grub/lvm boot bug #743126" ==>
		"/etc/default/grub" `File.containsLine` "GRUB_DISABLE_LINUX_UUID=true"
		`onChange` cmdProperty "update-grub" []
		`onChange` cmdProperty "update-initramfs" ["-u"]
	, combineProperties "nuked cloudatcost cruft"
		[ File.notPresent "/etc/rc.local"
		, File.notPresent "/etc/init.d/S97-setup.sh"
		, User.nuked "user" User.YesReallyDeleteHome
		]
	]

myDnsSecondary :: [Dns.Zone]
myDnsSecondary =
	[ Dns.secondary "kitenet.net" master
	, Dns.secondary "joeyh.name" master
	, Dns.secondary "ikiwiki.info" master
	, Dns.secondary "olduse.net" master
	, Dns.secondary "branchable.com" branchablemaster
	]
  where
	master = ["80.68.85.49", "2001:41c8:125:49::10"] -- wren
	branchablemaster = ["66.228.46.55", "2600:3c03::f03c:91ff:fedf:c0e5"]

main :: IO ()
main = defaultMain hosts --, Docker.containerProperties container]