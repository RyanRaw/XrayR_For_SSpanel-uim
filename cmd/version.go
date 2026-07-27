package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
	"github.com/xtls/xray-core/core"
)

var (
	version  = "0.9.6"
	codename = "XrayR"
	intro    = "A Xray backend that supports many panels"
)

func init() {
	rootCmd.AddCommand(&cobra.Command{
		Use:   "version",
		Short: "Print current version of XrayR",
		Run: func(cmd *cobra.Command, args []string) {
			showVersion()
		},
	})
}

func showVersion() {
	fmt.Printf("%s %s (%s)\n", codename, version, intro)
	fmt.Printf("Xray-core %s\n", core.Version())
}
