/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <rvlab.h>

#define LINE_SIZE 256
char *readline(void) {
    static char line[LINE_SIZE];
    int line_idx = 0;

    printf("> ");

    while(1) {
        int c=fgetc(stdin);
        
        if(c=='\n' || c=='\r') {
            fputc('\n', stdout);
            break;
        } else if (c==127) { // backspace
            if(line_idx > 0) {
                printf("\10\33[K");
                line_idx--;
            }
        } else if (c=='\x1b') {
            // Idea here is to ignore ANSI escape sequences coming from the user keyboard:
            while(1) {
                c = fgetc(stdin);
                if(c>='A' && c<='D') { // arrow up, down, left, right
                    break;
                }
            }
        } else {
            if(line_idx < LINE_SIZE - 1) {
                fputc(c, stdout);
                //printf("char %d\n", c);
                line[line_idx++] = c;
            }
        }
    }
    line[line_idx] = '\0';
    return line;

}

void cmd_help(char *args[]);
void cmd_lw(char *args[]);
void cmd_sw(char *args[]);
void cmd_dump(char *args[]);
void cmd_clear_fb(char *args[]);
void cmd_disable_hdmi(char *args[]);
void cmd_enable_hdmi(char *args[]);

struct cmd {
    char *name;
    char *help;
    int nargs;
    void (*handler) (char *args[]);
} cmds[] = {
    {"help", ": Print help.", 0, cmd_help},
    {"lw", " ADDR: Load word.", 1, cmd_lw},
    {"sw", " ADDR DATA: Store word.", 2, cmd_sw},
    {"dump", " ADDR WORDS: Dump memory.", 2, cmd_dump},
    {"frame_clear", " FBID R G B: Clear Frame Buffer.", 4, cmd_clear_fb},
    {"hdmi_off", ": Turn off Monitor.", 0, cmd_disable_hdmi},
    {"hdmi_on", ": Turn on Monitor.", 0, cmd_enable_hdmi},
    {NULL, NULL, 0, NULL}
};

void cmd_help(char *args[]) {
    printf("Help:\n");
    struct cmd *c;
        
    for(c = cmds;c->name;c++) {
        printf("\t%s%s\n", c->name, c->help);
    }   
}

void cmd_lw(char *args[]) {
    char *endptr;

    unsigned addr, data;

    addr = strtoul(args[1], &endptr, 0);
    if(*args[1]=='\0' || *endptr!='\0') {
        printf("Error: Failed to parse ADDR.\n");
        return;
    }

    data = *((unsigned *) addr);

    printf("read 0x%08x: 0x%08x\n", addr, data);
}

void cmd_dump(char *args[]) {
    char *endptr;

    unsigned addr, size, data;

    addr = strtoul(args[1], &endptr, 0);
    if(*args[1]=='\0' || *endptr!='\0') {
        printf("Error: Failed to parse ADDR.\n");
        return;
    }

    size = strtoul(args[2], &endptr, 0);
    if(*args[2]=='\0' || *endptr!='\0') {
        printf("Error: Failed to parse DATA.\n");
        return;
    }

    int i;
    for(i=0;i<size;i++) {
        data = *((unsigned char *) addr);
        if((i&0xf) == 0) {
            printf("\n%08x:", addr);
        }
        printf(" %02x", data);
        addr+=1;
    }
    printf("\n");
}


void cmd_sw(char *args[]) {
    char *endptr;

    unsigned addr, data;

    addr = strtoul(args[1], &endptr, 0);
    if(*args[1]=='\0' || *endptr!='\0') {
        printf("Error: Failed to parse ADDR.\n");
        return;
    }

    data = strtoul(args[2], &endptr, 0);
    if(*args[2]=='\0' || *endptr!='\0') {
        printf("Error: Failed to parse DATA.\n");
        return;
    }

    *((unsigned *) addr) = data;

    printf("wrote 0x%08x: 0x%08x\n", addr, data);
}


void cmd_clear_fb(char *args[]) {
    unsigned char r, g, b;
    unsigned char fbid;

    fbid = atoi(args[1]);
    r = atoi(args[2]);
    g = atoi(args[3]);
    b = atoi(args[4]);

    printf("Filling FB %u with R=%03u, G=%03u, B=%03u\n", fbid, r, g, b);

    REG32(FRAMECLEAR_DMA_FBID(0)) = fbid;
    REG32(FRAMECLEAR_DMA_CLEAR_COLOR(0)) = (r << 16) | (g << 8) | (b << 0);
    REG32(FRAMECLEAR_DMA_MODE(0)) = 0;
    REG32(FRAMECLEAR_DMA_STATUS(0)) = 1;

    uint32_t start = read_csr("mcycle");

    while (REG32(FRAMECLEAR_DMA_STATUS(0)));

    uint32_t finish = read_csr("mcycle");

    printf("Took %u cycles!\n", finish - start);

    REG32(HDMI_CTRL_FBID(0)) = fbid;
}

void cmd_disable_hdmi(char *args[]) {
    REG32(HDMI_CTRL_CTRL(0)) = 0;
}

void cmd_enable_hdmi(char *args[]) {
    REG32(HDMI_CTRL_CTRL(0)) |= (1<<HDMI_CTRL_CTRL_PHY_ENABLE_LSB);
    REG32(HDMI_CTRL_CTRL(0)) |= (1<<HDMI_CTRL_CTRL_FETCH_ENABLE_LSB);
}


int main(void) {
    ddr_init();
    REG32(HDMI_CTRL_CTRL(0)) |= (1<<HDMI_CTRL_CTRL_PHY_ENABLE_LSB);
    REG32(HDMI_CTRL_CTRL(0)) |= (1<<HDMI_CTRL_CTRL_FETCH_ENABLE_LSB);

    printf("Welcome to rvlab monitor.\n");

    while(1) {
        char *cmd = readline();
        char *args[5];
        struct cmd *c;
        args[0] = strtok(cmd," ");

        for(c = cmds;c->name;c++) {
            if(strcmp(args[0], c->name)==0)
                break;
        }
        if(!c->handler) {
            printf("Unknown command. Use 'help' for help.\n");
            c = NULL;
        }
        if(c) {
            for(int i=0;i<c->nargs;i++) {
                if((args[i+1] = strtok(NULL, " "))==NULL) {
                    printf("Too few arguments provided to %s.\n", c->name);
                    c = NULL;
                    break;
                }
            }
        }
        if(c) {
            if(strtok(NULL, " ")!=NULL) {
                printf("Too many arguments provided to %s.\n", c->name);
                c = NULL;
            }
        }
        if(c) {
            c->handler(args);
        }
    }
    return 0;
}
