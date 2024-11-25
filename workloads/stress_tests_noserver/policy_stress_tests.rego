package policy

import future.keywords.every
import future.keywords.in

api_version := "0.10.0"
framework_version := "0.2.3"

fragments := [
  {
    "feed": "mcr.microsoft.com/aci/aci-cc-infra-fragment",
    "includes": [
      "containers",
      "fragments"
    ],
    "issuer": "did:x509:0:sha256:I__iuL25oXEVFdTP_aBLx_eT1RPHbCQ_ECBQfYZpt9s::eku:1.3.6.1.4.1.311.76.59.1.3",
    "minimum_svn": "1"
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
      "/bin/bash",
      "workload_fio.sh"
    ],
    "env_rules": [
      {
        "pattern": "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "required": false,
        "strategy": "string"
      },
      {
        "pattern": "PORT=8000",
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
    "exec_processes": [
      {
        "command": [
          "/bin/sh"
        ],
        "signals": []
      },
      {
        "command": [
          "/bin/bash"
        ],
        "signals": []
      }
    ],
    "id": "cacidashboard.azurecr.io/stress_tests_noserver/workload:latest",
    "layers": [
      "b085957717abffbf057807d93b5a21d63109d4078c738bc77a1aeddb9e2b124e",
      "bef7c978a049d39217d920effb20fa4bf883a36cb1de46d51e6e2b8bfc79b810",
      "f7fc57d629ba280a9879a7debc6515243afb84d99d096566734595533e374eb0",
      "d14d166a2d12aed04b0b2351e12d577abe9caeb6f6d3d6701b4186ebd573c44e",
      "d7c41cc4417288c710da9371e661d687e4bd9bb6121b196dcea6b5a0340bf855"
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
    "name": "workload",
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
    "working_dir": "/var/www"
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
      "/bin/sleep",
      "infinity"
    ],
    "env_rules": [
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
    "exec_processes": [
      {
        "command": [
          "/bin/sh"
        ],
        "signals": []
      },
      {
        "command": [
          "/bin/bash"
        ],
        "signals": []
      }
    ],
    "id": "mcr.microsoft.com/aci/skr:2.7",
    "layers": [
      "c2d669f165d21e3547d7a9452df3f1e602a92f15395be781b8b05e38c0959f49",
      "ea92f7f56267bb282023d097e9809488ec9141f01135dd771607d1bf6c6622f5",
      "9fe14782c961dc911f0c49c227448d805772a9ac3f1e285366d72eb24d98cc95",
      "b01b044a9ba42f1da128bdb46e21bf04466fb2cc36d24e22751c75922a943e40",
      "b98267f62b738736c201e8173fbc8d723bd46743e17ab3194479e35cc98dfd7f",
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
    "name": "sidecar",
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
allow_dump_stacks := true
allow_runtime_logging := true
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

reason := {"errors": data.framework.errors}


