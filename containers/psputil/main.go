package main

import (
	"fmt"
	"os"
	"strings"
	"unsafe"

	"golang.org/x/sys/windows"
)

// ref: https://github.com/microsoft/confidential-containers-containerd/blob/af0e41d755a48c73b25c809ecdd418a9a6e78363/cmd/containerd/command/service_windows.go#L46

var (
	// NewLazyDLL (not NewLazySystemDLL): amdsnppspapi.dll is bundled into the
	// image next to this exe (/app), not present in the container's System32.
	// NewLazySystemDLL forces a System32-only search and would panic with "The
	// specified module could not be found" on the first .Call(). NewLazyDLL uses
	// the default DLL search order, which includes the executable's directory.
	amdsnppspapi = windows.NewLazyDLL("amdsnppspapi.dll")
	// It will panic if the function is not found when .Call() is called.
	isSnpModeProc              = amdsnppspapi.NewProc("SnpPspIsSnpMode")
	fetchAttestationReportProc = amdsnppspapi.NewProc("SnpPspFetchAttestationReport")
)

const (
	SNPPSP_API_REPORT_DATA_SIZE                    = 64
	SNPPSP_API_ATTESTATION_REPORT_SIZE             = 0x4A0
	SNPPSP_API_REPORT_CURRENT_TCB_SIZE             = 8
	SNPPSP_API_REPORT_MEASUREMENT_SIZE             = 48
	SNPPSP_API_REPORT_HOST_DATA_SIZE               = 32
	SNPPSP_API_REPORT_ID_KEY_DIGEST_SIZE           = 48
	SNPPSP_API_REPORT_AUTHOR_KEY_DIGEST_SIZE       = 48
	SNPPSP_API_REPORT_SNPPSP_API_REPORT_ID_SIZE    = 32
	SNPPSP_API_REPORT_SNPPSP_API_REPORT_ID_MA_SIZE = 32
	SNPPSP_API_REPORT_REPORTED_TCB_SIZE            = 8
	SNPPSP_API_REPORT_RESERVED2_SIZE               = 21
	SNPPSP_API_REPORT_CHIP_ID_SIZE                 = 64
	SNPPSP_API_REPORT_COMMITTED_TCB_SIZE           = 8
	SNPPSP_API_REPORT_LAUNCH_TCB_SIZE              = 8
	SNPPSP_API_REPORT_RESERVED5_SIZE               = 168
	SNPPSP_API_REPORT_SIGNATURE_SIZE               = 512
)

const (
	SNPPSP_API_STATUS_SUCCESS              = 0x00000000
	SNPPSP_API_STATUS_UNSUCCESSFUL         = 0x00000001
	SNPPSP_API_STATUS_DRIVER_UNSUCCESSFUL  = 0x00000003
	SNPPSP_API_STATUS_PSP_UNSUCCESSFUL     = 0x00000004
	SNPPSP_API_STATUS_INVALID_PARAMETER    = 0x00000005
	SNPPSP_API_STATUS_DEVICE_NOT_AVAILABLE = 0x00000006
)

type SNPPSPUINT128 struct {
	Lo uint64
	Hi uint64
}

type SNPPSPGuestRequestResult struct {
	DriverStatus uint32
	PspStatus    uint64
}

type SNPAttestationReport struct {
	Version         uint32
	GuestSvn        uint32
	Policy          uint64
	FamilyId        SNPPSPUINT128
	ImageId         SNPPSPUINT128
	Vmpl            uint32
	SignatureAlgo   uint32
	CurrentTcb      [SNPPSP_API_REPORT_CURRENT_TCB_SIZE]uint8
	PlatformInfo    uint64
	AuthorKeyEn     uint32
	Reserved1       uint32
	ReportData      [SNPPSP_API_REPORT_DATA_SIZE]uint8
	Measurement     [SNPPSP_API_REPORT_MEASUREMENT_SIZE]uint8
	HostData        [SNPPSP_API_REPORT_HOST_DATA_SIZE]uint8
	IdKeyDigest     [SNPPSP_API_REPORT_ID_KEY_DIGEST_SIZE]uint8
	AuthorKeyDigest [SNPPSP_API_REPORT_AUTHOR_KEY_DIGEST_SIZE]uint8
	ReportId        [SNPPSP_API_REPORT_SNPPSP_API_REPORT_ID_SIZE]uint8
	ReportIdMa      [SNPPSP_API_REPORT_SNPPSP_API_REPORT_ID_MA_SIZE]uint8
	ReportedTcb     [SNPPSP_API_REPORT_REPORTED_TCB_SIZE]uint8
	CpuidFamId      uint8
	CpuidModId      uint8
	CpuidStep       uint8
	Reserved2       [SNPPSP_API_REPORT_RESERVED2_SIZE]uint8
	ChipId          [SNPPSP_API_REPORT_CHIP_ID_SIZE]uint8
	CommittedTcb    [SNPPSP_API_REPORT_COMMITTED_TCB_SIZE]uint8
	CurrentBuild    uint8
	CurrentMinor    uint8
	CurrentMajor    uint8
	Reserved3       uint8
	CommittedBuild  uint8
	CommittedMinor  uint8
	CommittedMajor  uint8
	Reserved4       uint8
	LaunchTcb       [SNPPSP_API_REPORT_LAUNCH_TCB_SIZE]uint8
	Reserved5       [SNPPSP_API_REPORT_RESERVED5_SIZE]uint8
	Signature       [SNPPSP_API_REPORT_SIGNATURE_SIZE]uint8
}

// DLL function types
type SnpPspFetchAttestationReportFunc func(
	reportData *[SNPPSP_API_REPORT_DATA_SIZE]uint8,
	result *SNPPSPGuestRequestResult,
	report *[SNPPSP_API_ATTESTATION_REPORT_SIZE]uint8,
) uint32

type SnpPspIsSnpModeFunc func(isSnp *uint8) uint32

func printBytesToString(desc string, data []uint8, swap bool) {
	fmt.Printf("  %s: ", desc)
	padding := 20 - len(desc)
	if padding < 0 {
		padding = 0
	}
	for i := 0; i < padding; i++ {
		fmt.Print(" ")
	}

	for pos := 0; pos < len(data); pos++ {
		var byteVal uint8
		if swap {
			byteVal = data[len(data)-pos-1]
		} else {
			byteVal = data[pos]
		}
		fmt.Printf("%02x", byteVal)
		if pos%32 == 31 && pos != len(data)-1 {
			fmt.Print("\n                        ")
		} else if pos%16 == 15 && pos != len(data)-1 {
			fmt.Print(" ")
		}
	}
	fmt.Println()
}

func toByteSlice(data interface{}) []uint8 {
	switch v := data.(type) {
	case uint8:
		return unsafe.Slice(&v, 1)
	case uint32:
		return unsafe.Slice((*uint8)(unsafe.Pointer(&v)), 4)
	case uint64:
		return unsafe.Slice((*uint8)(unsafe.Pointer(&v)), 8)
	case SNPPSPUINT128:
		return unsafe.Slice((*uint8)(unsafe.Pointer(&v)), 16)
	default:
		panic("unsupported type")
	}
}

func printReport(report *SNPAttestationReport) {
	printBytesToString("Version", toByteSlice(report.Version), true)
	printBytesToString("GuestSvn", toByteSlice(report.GuestSvn), true)
	printBytesToString("Policy", toByteSlice(report.Policy), true)
	printBytesToString("FamilyId", toByteSlice(report.FamilyId), true)
	printBytesToString("ImageId", toByteSlice(report.ImageId), true)
	printBytesToString("Vmpl", toByteSlice(report.Vmpl), true)
	printBytesToString("SignatureAlgo", toByteSlice(report.SignatureAlgo), true)
	printBytesToString("CurrentTcb", report.CurrentTcb[:], true)
	printBytesToString("PlatformInfo", toByteSlice(report.PlatformInfo), true)
	printBytesToString("AuthorKeyEn", toByteSlice(report.AuthorKeyEn), true)
	printBytesToString("Reserved1", toByteSlice(report.Reserved1), false)
	printBytesToString("ReportData", report.ReportData[:], false)
	printBytesToString("Measurement", report.Measurement[:], false)
	printBytesToString("HostData", report.HostData[:], false)
	printBytesToString("IdKeyDigest", report.IdKeyDigest[:], false)
	printBytesToString("AuthorKeyDigest", report.AuthorKeyDigest[:], false)
	printBytesToString("ReportId", report.ReportId[:], false)
	printBytesToString("ReportIdMa", report.ReportIdMa[:], false)
	printBytesToString("ReportedTcb", report.ReportedTcb[:], true)
	printBytesToString("CpuidFamId", toByteSlice(report.CpuidFamId), true)
	printBytesToString("CpuidModId", toByteSlice(report.CpuidModId), true)
	printBytesToString("CpuidStep", toByteSlice(report.CpuidStep), true)
	printBytesToString("Reserved2", report.Reserved2[:], false)
	printBytesToString("ChipId", report.ChipId[:], false)
	printBytesToString("CommittedTcb", report.CommittedTcb[:], true)
	printBytesToString("CurrentBuild", toByteSlice(report.CurrentBuild), true)
	printBytesToString("CurrentMinor", toByteSlice(report.CurrentMinor), true)
	printBytesToString("CurrentMajor", toByteSlice(report.CurrentMajor), true)
	printBytesToString("Reserved3", toByteSlice(report.Reserved3), false)
	printBytesToString("CommittedBuild", toByteSlice(report.CommittedBuild), true)
	printBytesToString("CommittedMinor", toByteSlice(report.CommittedMinor), true)
	printBytesToString("CommittedMajor", toByteSlice(report.CommittedMajor), true)
	printBytesToString("Reserved4", toByteSlice(report.Reserved4), false)
	printBytesToString("LaunchTcb", report.LaunchTcb[:], true)
	printBytesToString("Reserved5", report.Reserved5[:], false)
	printBytesToString("Signature", report.Signature[:], false)
}

func printCertUrl(report *SNPAttestationReport) {
	const endpoint = "kdsintf.amd.com"
	const teeType = "vcek/v1/Milan"

	const (
		BlSplTcbmByteIndex    = 0
		TeeSplTcbmByteIndex   = 1
		TcbSpl_4TcbmByteIndex = 2
		TcbSpl_5TcbmByteIndex = 3
		TcbSpl_6TcbmByteIndex = 4
		TcbSpl_7TcbmByteIndex = 5
		SnpSplTcbmByteIndex   = 6
		UcodeSplTcbmByteIndex = 7
	)

	var chipIdBuilder strings.Builder
	for _, b := range report.ChipId {
		chipIdBuilder.WriteString(fmt.Sprintf("%02x", b))
	}
	chipId := chipIdBuilder.String()

	fmt.Printf("https://%s/%s/%s?ucodeSPL=%d&snpSPL=%d&teeSPL=%d&blSPL=%d\n",
		endpoint,
		teeType,
		chipId,
		report.ReportedTcb[UcodeSplTcbmByteIndex],
		report.ReportedTcb[SnpSplTcbmByteIndex],
		report.ReportedTcb[TeeSplTcbmByteIndex],
		report.ReportedTcb[BlSplTcbmByteIndex])
}

func main() {
	var printReportFlag, getCertUrlFlag bool

	for _, arg := range os.Args[1:] {
		switch arg {
		case "--PrintReport":
			printReportFlag = true
		case "--PrintCertUrl":
			getCertUrlFlag = true
		}
	}

	// Check if we're in SNP mode. If not we can't proceed.
	var snpMode uint8
	ret, _, _ := isSnpModeProc.Call(uintptr(unsafe.Pointer(&snpMode)))
	if ret != SNPPSP_API_STATUS_SUCCESS {
		fmt.Printf("Failed to determine if it's in SNP VM. SNPPSP_API_STATUS: 0x%x\n", ret)
		os.Exit(1)
	}

	if snpMode == 0 {
		fmt.Println("It's not in SNP environment.")
		os.Exit(1)
	}

	// Prepare report data
	reportDataText := "hello world"
	var reportData [SNPPSP_API_REPORT_DATA_SIZE]uint8
	copy(reportData[:], []byte(reportDataText))

	var report [SNPPSP_API_ATTESTATION_REPORT_SIZE]uint8
	var guestRequestResult SNPPSPGuestRequestResult

	// Fetch attestation report
	ret, _, _ = fetchAttestationReportProc.Call(
		uintptr(unsafe.Pointer(&reportData[0])),
		uintptr(unsafe.Pointer(&guestRequestResult)),
		uintptr(unsafe.Pointer(&report[0])))

	if ret != SNPPSP_API_STATUS_SUCCESS {
		fmt.Printf("Failed to fetch attestation report. res: 0x%x, DriverStatus: 0x%x, PspStatus: 0x%x\n",
			ret, guestRequestResult.DriverStatus, guestRequestResult.PspStatus)
		os.Exit(1)
	}

	reportStruct := (*SNPAttestationReport)(unsafe.Pointer(&report[0]))

	if printReportFlag {
		printReport(reportStruct)
	}

	if getCertUrlFlag {
		printCertUrl(reportStruct)
	}
}
