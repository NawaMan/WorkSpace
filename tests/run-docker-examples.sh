#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Check if docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
    exit 1
fi

# Check if Go is available
if ! command -v go &> /dev/null; then
    echo -e "${RED}Error: Go is not installed or not in PATH${NC}"
    exit 1
fi

show_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║          Docker Package - Manual Examples Runner          ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

show_menu() {
    echo -e "${BLUE}Available Examples:${NC}"
    echo
    echo "  1) Pull hello-world Image"
    echo "  2) Run hello-world Container"
    echo "  3) Run Echo Command in Alpine"
    echo "  4) Run Alpine with Environment Variable"
    echo "  5) Inspect Docker Image"
    echo "  6) List All Containers"
    echo "  7) Network Operations (Create/Inspect/Remove)"
    echo "  8) Complex Docker Command"
    echo "  9) Interactive Shell with -it Flags (TTY Detection Demo)"
    echo " 10) Build Docker Image"
    echo " 11) Run Container in Daemon Mode"
    echo " 12) Stop Running Container"
    echo
    echo "  a) Run ALL examples in sequence"
    echo "  q) Quit"
    echo
}

run_example() {
    local example_name="$1"
    local example_num="$2"
    
    echo
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Running Example ${example_num}...${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    
    cd "$SCRIPT_DIR"
    if go test -v ./src/pkg/docker/... -run "^${example_name}$" 2>&1 2>&1; then
        echo
        echo -e "${GREEN}✅ Example completed successfully${NC}"
    else
        echo
        echo -e "${RED}❌ Example failed${NC}"
    fi
    
    echo
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

run_all_examples() {
    echo -e "${CYAN}Running all examples in sequence...${NC}"
    echo
    
    run_example "TestManual_pullHelloWorld" "1"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestManual_runHelloWorld" "2"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestManual_runAlpineEcho" "3"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestManual_runAlpineWithEnv" "4"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestManual_imageInspect" "5"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestManual_listContainers" "6"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestManual_networkOperations" "7"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestManual_complexCommand" "8"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestManual_interactiveShell" "9"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestManual_buildImage" "10"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestManual_runDaemon" "11"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestManual_stopContainer" "12"
    
    echo -e "${GREEN}✅ All examples completed!${NC}"
}

main() {
    show_banner
    
    while true; do
        show_menu
        read -p "Select an example (1-12, a, q): " choice
        
        case $choice in
            1)
                run_example "TestManual_pullHelloWorld" "1"
                read -p "Press Enter to return to menu..."
                ;;
            2)
                run_example "TestManual_runHelloWorld" "2"
                read -p "Press Enter to return to menu..."
                ;;
            3)
                run_example "TestManual_runAlpineEcho" "3"
                read -p "Press Enter to return to menu..."
                ;;
            4)
                run_example "TestManual_runAlpineWithEnv" "4"
                read -p "Press Enter to return to menu..."
                ;;
            5)
                run_example "TestManual_imageInspect" "5"
                read -p "Press Enter to return to menu..."
                ;;
            6)
                run_example "TestManual_listContainers" "6"
                read -p "Press Enter to return to menu..."
                ;;
            7)
                run_example "TestManual_networkOperations" "7"
                read -p "Press Enter to return to menu..."
                ;;
            8)
                run_example "TestManual_complexCommand" "8"
                read -p "Press Enter to return to menu..."
                ;;
            9)
                run_example "TestManual_interactiveShell" "9"
                read -p "Press Enter to return to menu..."
                ;;
            10)
                run_example "TestManual_buildImage" "10"
                read -p "Press Enter to return to menu..."
                ;;
            11)
                run_example "TestManual_runDaemon" "11"
                read -p "Press Enter to return to menu..."
                ;;
            12)
                run_example "TestManual_stopContainer" "12"
                read -p "Press Enter to return to menu..."
                ;;
            a|A)
                run_all_examples
                read -p "Press Enter to return to menu..."
                ;;
            q|Q)
                echo
                echo -e "${CYAN}Goodbye!${NC}"
                echo
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please select 1-12, a, or q.${NC}"
                sleep 1
                ;;
        esac
        
        clear
        show_banner
    done
}

# Run main function
main
