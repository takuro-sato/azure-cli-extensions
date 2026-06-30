package policy

import future.keywords.every
import future.keywords.in

api_version := "0.11.0"
framework_version := "0.2.3"

fragments := [
  {
    "feed": "mcr.microsoft.com/aci/aci-cc-infra-fragment",
    "includes": [
      "containers",
      "fragments"
    ],
    "issuer": "did:x509:0:sha256:I__iuL25oXEVFdTP_aBLx_eT1RPHbCQ_ECBQfYZpt9s::eku:1.3.6.1.4.1.311.76.59.1.3",
    "minimum_svn": "4"
  }
]

containers := [
  {
    "allow_elevated": false,
    "allow_stdio_access": true,
    "capabilities": {
      "ambient": [],
      "bounding": [
        "CAP_AUDIT_WRITE",
        "CAP_CHOWN",
        "CAP_DAC_OVERRIDE",
        "CAP_FOWNER",
        "CAP_FSETID",
        "CAP_KILL",
        "CAP_MKNOD",
        "CAP_NET_BIND_SERVICE",
        "CAP_NET_RAW",
        "CAP_SETFCAP",
        "CAP_SETGID",
        "CAP_SETPCAP",
        "CAP_SETUID",
        "CAP_SYS_CHROOT"
      ],
      "effective": [
        "CAP_AUDIT_WRITE",
        "CAP_CHOWN",
        "CAP_DAC_OVERRIDE",
        "CAP_FOWNER",
        "CAP_FSETID",
        "CAP_KILL",
        "CAP_MKNOD",
        "CAP_NET_BIND_SERVICE",
        "CAP_NET_RAW",
        "CAP_SETFCAP",
        "CAP_SETGID",
        "CAP_SETPCAP",
        "CAP_SETUID",
        "CAP_SYS_CHROOT"
      ],
      "inheritable": [],
      "permitted": [
        "CAP_AUDIT_WRITE",
        "CAP_CHOWN",
        "CAP_DAC_OVERRIDE",
        "CAP_FOWNER",
        "CAP_FSETID",
        "CAP_KILL",
        "CAP_MKNOD",
        "CAP_NET_BIND_SERVICE",
        "CAP_NET_RAW",
        "CAP_SETFCAP",
        "CAP_SETGID",
        "CAP_SETPCAP",
        "CAP_SETUID",
        "CAP_SYS_CHROOT"
      ]
    },
    "command": [
      "python3",
      "proxy.py"
    ],
    "env_rules": [
      {
        "pattern": "PATH=/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "PYTHON_VERSION=3.14.5",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "PYTHON_SHA256=7e32597b99e5d9a39abed35de4693fa169df3e5850d4c334337ffd6a19a36db6",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "TERM=xterm",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "(?i)(FABRIC)_.+=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "HOSTNAME=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "T(E)?MP=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "FabricPackageFileName=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "HostedServiceName=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "IDENTITY_API_VERSION=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "IDENTITY_HEADER=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "IDENTITY_SERVER_THUMBPRINT=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "azurecontainerinstance_restarted_by=.+",
        "required": false,
        "strategy": "re2"
      }
    ],
    "exec_processes": [],
    "id": "cacidashboardaci.azurecr.io/prebuilt-test-containers/skr_proxy:skr-fixed-policy",
    "layers": [
      "4264fef0a6d05a59bb036a53bc76e687c3cadb4b983dd106c357ae612c1251ae",
      "4a9d6b2957ab386cc5d72dfb571917e006ecd9a85a0ec376842404f6baf90141",
      "8f71b6b8874d2b4ed36c7d87969a432854e89af22c58c5b231593112c56fda00",
      "7f77dd75f6c07897b125dd048aaf4d5313ae196512d0ecd627761438feadabc7",
      "a13be63b1ccba616bbb59a2bd1b509dca7ab4fdbf3bd4c8dcae74ff7bb964a75",
      "59f9a8d03165f645eed4cadcfb7338ae841263c67e09c4e6598a0310ef232c5f",
      "75c69e172704e5b477f6afe57dbdc0e8b347bc3d169219af400752e0f165f3aa",
      "9031342fcb51646827996de516e3b4d14dec944b551ddd66b27ad32da0b94d49",
      "cbf8024ecf6f079a794ea98aaa73acf085f91b6858da10a119e0f5682c9b937b",
      "659b0bd4b307307bd1820ebeb99721d4c285f7b37521736ab7b3930d1a7867aa",
      "7254a102224a4312d84d53e495935218310a58c827243923ff9dec9210e2fe3e"
    ],
    "mounts": [
      {
        "destination": "/etc/resolv.conf",
        "options": [
          "rbind",
          "rshared",
          "rw"
        ],
        "source": "sandbox:///tmp/atlas/resolvconf/.+",
        "type": "bind"
      }
    ],
    "name": "proxy",
    "no_new_privileges": false,
    "seccomp_profile_sha256": "",
    "signals": [],
    "user": {
      "group_idnames": [
        {
          "pattern": "",
          "strategy": "any"
        }
      ],
      "umask": "0022",
      "user_idname": {
        "pattern": "",
        "strategy": "any"
      }
    },
    "working_dir": "/usr/src/app"
  },
  {
    "allow_elevated": false,
    "allow_stdio_access": true,
    "capabilities": {
      "ambient": [],
      "bounding": [
        "CAP_AUDIT_WRITE",
        "CAP_CHOWN",
        "CAP_DAC_OVERRIDE",
        "CAP_FOWNER",
        "CAP_FSETID",
        "CAP_KILL",
        "CAP_MKNOD",
        "CAP_NET_BIND_SERVICE",
        "CAP_NET_RAW",
        "CAP_SETFCAP",
        "CAP_SETGID",
        "CAP_SETPCAP",
        "CAP_SETUID",
        "CAP_SYS_CHROOT"
      ],
      "effective": [
        "CAP_AUDIT_WRITE",
        "CAP_CHOWN",
        "CAP_DAC_OVERRIDE",
        "CAP_FOWNER",
        "CAP_FSETID",
        "CAP_KILL",
        "CAP_MKNOD",
        "CAP_NET_BIND_SERVICE",
        "CAP_NET_RAW",
        "CAP_SETFCAP",
        "CAP_SETGID",
        "CAP_SETPCAP",
        "CAP_SETUID",
        "CAP_SYS_CHROOT"
      ],
      "inheritable": [],
      "permitted": [
        "CAP_AUDIT_WRITE",
        "CAP_CHOWN",
        "CAP_DAC_OVERRIDE",
        "CAP_FOWNER",
        "CAP_FSETID",
        "CAP_KILL",
        "CAP_MKNOD",
        "CAP_NET_BIND_SERVICE",
        "CAP_NET_RAW",
        "CAP_SETFCAP",
        "CAP_SETGID",
        "CAP_SETPCAP",
        "CAP_SETUID",
        "CAP_SYS_CHROOT"
      ]
    },
    "command": [
      "/skr.sh"
    ],
    "env_rules": [
      {
        "pattern": "LogLevel=debug",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "SkrSideCarArgs=eyJtYWFjb25maWciOnsidXNlcl9hZ2VudCI6ImNvbmZpZGVudGlhbC1hY2ktdGVzdGluZyJ9fQ==",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "BUILD_DIR=/go/src/github.com/microsoft/confidential-sidecar-containers",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "TERM=xterm",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "(?i)(FABRIC)_.+=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "HOSTNAME=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "T(E)?MP=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "FabricPackageFileName=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "HostedServiceName=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "IDENTITY_API_VERSION=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "IDENTITY_HEADER=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "IDENTITY_SERVER_THUMBPRINT=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "azurecontainerinstance_restarted_by=.+",
        "required": false,
        "strategy": "re2"
      }
    ],
    "exec_processes": [],
    "id": "mcr.microsoft.com/aci/skr:2.14",
    "layers": [
      "a189b02d4858578459fda1dfbd7c6a4557c44208b9829e02b931771a6d611c39",
      "300f9661fb3d46c0f299ad6f552b7ad0c41ea5141755b0b3feaca3081a108f7a",
      "0afffca98bacf8e7b6e6f7982459a03219f60555523163c73c4b092e0a3deef2",
      "eefefd5009aed4ba4478876995d1a18aa3a670661fcc61d2e4cba6e2b79da0a1",
      "b868a7e1bebef40e5bf4d58fe271c0a10a351e68b12179ec019af9f6c75781ae",
      "8b4842f06982817534a75bcf71865213b09dfa8313229c384e5201dadbd75e25"
    ],
    "mounts": [
      {
        "destination": "/etc/resolv.conf",
        "options": [
          "rbind",
          "rshared",
          "rw"
        ],
        "source": "sandbox:///tmp/atlas/resolvconf/.+",
        "type": "bind"
      }
    ],
    "name": "http-sidecar",
    "no_new_privileges": false,
    "seccomp_profile_sha256": "",
    "signals": [],
    "user": {
      "group_idnames": [
        {
          "pattern": "",
          "strategy": "any"
        }
      ],
      "umask": "0022",
      "user_idname": {
        "pattern": "",
        "strategy": "any"
      }
    },
    "working_dir": "/"
  },
  {
    "allow_elevated": false,
    "allow_stdio_access": true,
    "capabilities": {
      "ambient": [],
      "bounding": [
        "CAP_AUDIT_WRITE",
        "CAP_CHOWN",
        "CAP_DAC_OVERRIDE",
        "CAP_FOWNER",
        "CAP_FSETID",
        "CAP_KILL",
        "CAP_MKNOD",
        "CAP_NET_BIND_SERVICE",
        "CAP_NET_RAW",
        "CAP_SETFCAP",
        "CAP_SETGID",
        "CAP_SETPCAP",
        "CAP_SETUID",
        "CAP_SYS_CHROOT"
      ],
      "effective": [
        "CAP_AUDIT_WRITE",
        "CAP_CHOWN",
        "CAP_DAC_OVERRIDE",
        "CAP_FOWNER",
        "CAP_FSETID",
        "CAP_KILL",
        "CAP_MKNOD",
        "CAP_NET_BIND_SERVICE",
        "CAP_NET_RAW",
        "CAP_SETFCAP",
        "CAP_SETGID",
        "CAP_SETPCAP",
        "CAP_SETUID",
        "CAP_SYS_CHROOT"
      ],
      "inheritable": [],
      "permitted": [
        "CAP_AUDIT_WRITE",
        "CAP_CHOWN",
        "CAP_DAC_OVERRIDE",
        "CAP_FOWNER",
        "CAP_FSETID",
        "CAP_KILL",
        "CAP_MKNOD",
        "CAP_NET_BIND_SERVICE",
        "CAP_NET_RAW",
        "CAP_SETFCAP",
        "CAP_SETGID",
        "CAP_SETPCAP",
        "CAP_SETUID",
        "CAP_SYS_CHROOT"
      ]
    },
    "command": [
      "/skr.sh"
    ],
    "env_rules": [
      {
        "pattern": "ServerType=grpc",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "Port=50000",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "LogLevel=debug",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "SkrSideCarArgs=eyJtYWFjb25maWciOnsidXNlcl9hZ2VudCI6ImNvbmZpZGVudGlhbC1hY2ktdGVzdGluZyJ9fQ==",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "BUILD_DIR=/go/src/github.com/microsoft/confidential-sidecar-containers",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "TERM=xterm",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "(?i)(FABRIC)_.+=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "HOSTNAME=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "T(E)?MP=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "FabricPackageFileName=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "HostedServiceName=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "IDENTITY_API_VERSION=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "IDENTITY_HEADER=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "IDENTITY_SERVER_THUMBPRINT=.+",
        "required": false,
        "strategy": "re2"
      },
      {
        "pattern": "azurecontainerinstance_restarted_by=.+",
        "required": false,
        "strategy": "re2"
      }
    ],
    "exec_processes": [],
    "id": "mcr.microsoft.com/aci/skr:2.14",
    "layers": [
      "a189b02d4858578459fda1dfbd7c6a4557c44208b9829e02b931771a6d611c39",
      "300f9661fb3d46c0f299ad6f552b7ad0c41ea5141755b0b3feaca3081a108f7a",
      "0afffca98bacf8e7b6e6f7982459a03219f60555523163c73c4b092e0a3deef2",
      "eefefd5009aed4ba4478876995d1a18aa3a670661fcc61d2e4cba6e2b79da0a1",
      "b868a7e1bebef40e5bf4d58fe271c0a10a351e68b12179ec019af9f6c75781ae",
      "8b4842f06982817534a75bcf71865213b09dfa8313229c384e5201dadbd75e25"
    ],
    "mounts": [
      {
        "destination": "/etc/resolv.conf",
        "options": [
          "rbind",
          "rshared",
          "rw"
        ],
        "source": "sandbox:///tmp/atlas/resolvconf/.+",
        "type": "bind"
      }
    ],
    "name": "grpc-sidecar",
    "no_new_privileges": false,
    "seccomp_profile_sha256": "",
    "signals": [],
    "user": {
      "group_idnames": [
        {
          "pattern": "",
          "strategy": "any"
        }
      ],
      "umask": "0022",
      "user_idname": {
        "pattern": "",
        "strategy": "any"
      }
    },
    "working_dir": "/"
  },
  {
    "allow_elevated": false,
    "allow_stdio_access": true,
    "capabilities": {
      "ambient": [],
      "bounding": [
        "CAP_CHOWN",
        "CAP_DAC_OVERRIDE",
        "CAP_FSETID",
        "CAP_FOWNER",
        "CAP_MKNOD",
        "CAP_NET_RAW",
        "CAP_SETGID",
        "CAP_SETUID",
        "CAP_SETFCAP",
        "CAP_SETPCAP",
        "CAP_NET_BIND_SERVICE",
        "CAP_SYS_CHROOT",
        "CAP_KILL",
        "CAP_AUDIT_WRITE"
      ],
      "effective": [
        "CAP_CHOWN",
        "CAP_DAC_OVERRIDE",
        "CAP_FSETID",
        "CAP_FOWNER",
        "CAP_MKNOD",
        "CAP_NET_RAW",
        "CAP_SETGID",
        "CAP_SETUID",
        "CAP_SETFCAP",
        "CAP_SETPCAP",
        "CAP_NET_BIND_SERVICE",
        "CAP_SYS_CHROOT",
        "CAP_KILL",
        "CAP_AUDIT_WRITE"
      ],
      "inheritable": [],
      "permitted": [
        "CAP_CHOWN",
        "CAP_DAC_OVERRIDE",
        "CAP_FSETID",
        "CAP_FOWNER",
        "CAP_MKNOD",
        "CAP_NET_RAW",
        "CAP_SETGID",
        "CAP_SETUID",
        "CAP_SETFCAP",
        "CAP_SETPCAP",
        "CAP_NET_BIND_SERVICE",
        "CAP_SYS_CHROOT",
        "CAP_KILL",
        "CAP_AUDIT_WRITE"
      ]
    },
    "command": [
      "/pause"
    ],
    "env_rules": [
      {
        "pattern": "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "required": true,
        "strategy": "string"
      },
      {
        "pattern": "TERM=xterm",
        "required": false,
        "strategy": "string"
      }
    ],
    "exec_processes": [],
    "layers": [
      "16b514057a06ad665f92c02863aca074fd5976c755d26bff16365299169e8415"
    ],
    "mounts": [],
    "name": "pause-container",
    "no_new_privileges": false,
    "seccomp_profile_sha256": "",
    "signals": [],
    "user": {
      "group_idnames": [
        {
          "pattern": "",
          "strategy": "any"
        }
      ],
      "umask": "0022",
      "user_idname": {
        "pattern": "",
        "strategy": "any"
      }
    },
    "working_dir": "/"
  }
]

allow_properties_access := true
allow_dump_stacks := false
allow_runtime_logging := false
allow_environment_variable_dropping := true
allow_unencrypted_scratch := false
allow_capability_dropping := true

mount_device := data.framework.mount_device
unmount_device := data.framework.unmount_device
mount_overlay := data.framework.mount_overlay
unmount_overlay := data.framework.unmount_overlay
create_container := data.framework.create_container
exec_in_container := data.framework.exec_in_container
exec_external := data.framework.exec_external
shutdown_container := data.framework.shutdown_container
signal_container_process := data.framework.signal_container_process
plan9_mount := data.framework.plan9_mount
plan9_unmount := data.framework.plan9_unmount
get_properties := data.framework.get_properties
dump_stacks := data.framework.dump_stacks
runtime_logging := data.framework.runtime_logging
load_fragment := data.framework.load_fragment
scratch_mount := data.framework.scratch_mount
scratch_unmount := data.framework.scratch_unmount
rw_mount_device := data.framework.rw_mount_device

reason := {"errors": data.framework.errors}


