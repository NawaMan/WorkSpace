package main

import (
	"fmt"
	"os"
)

const version = "0.11.0"

func main() {
	fmt.Printf("WorkSpace v%s - Go Edition\n", version)
	fmt.Println("Hello, World!")

	// Exit successfully
	os.Exit(0)
}
