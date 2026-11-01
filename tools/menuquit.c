/*
 * menuquit - cierra un proceso al MANTENER un boton del mando (por defecto el boton Menu, indice 8).
 * Uso:  menuquit PID [boton=8] [mantener_ms=1000] [dispositivo=/dev/input/js0]
 * Lee la API de joystick de Linux (struct js_event). Envia SIGTERM (cierre limpio de SDL) y, si el proceso
 * sigue vivo a los 3 s, SIGKILL. Termina solo si el proceso objetivo muere. Licencia: MIT.
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

struct js_ev { uint32_t time; int16_t value; uint8_t type; uint8_t number; };

static long now_ms(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}
static int alive(pid_t p) { return kill(p, 0) == 0; }

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "uso: %s PID [boton=8] [mantener_ms=1000] [dispositivo]\n", argv[0]); return 2; }
    pid_t pid = (pid_t)atoi(argv[1]);
    int button = argc > 2 ? atoi(argv[2]) : 8;
    long hold = argc > 3 ? atol(argv[3]) : 1000;
    const char *devs[] = { argc > 4 ? argv[4] : "/dev/input/js0", "/dev/input/js1", "/dev/input/js2", "/dev/input/js3" };
    int ndevs = argc > 4 ? 1 : 4;
    int fd = -1;
    for (int i = 0; i < ndevs && fd < 0; i++) fd = open(devs[i], O_RDONLY | O_NONBLOCK);
    if (fd < 0) { fprintf(stderr, "[menuquit] no se pudo abrir el joystick: %s\n", strerror(errno)); return 1; }
    printf("[menuquit] vigilando el proceso %d: mantener el boton %d durante %ld ms para salir\n", (int)pid, button, hold);
    fflush(stdout);

    long pressed_at = -1;
    for (;;) {
        struct pollfd pfd = { fd, POLLIN, 0 };
        int r = poll(&pfd, 1, 100);
        if (!alive(pid)) return 0;
        if (r > 0 && (pfd.revents & POLLIN)) {
            struct js_ev e;
            while (read(fd, &e, sizeof e) == (ssize_t)sizeof e) {
                if (e.type == 0x01 && e.number == button) {   /* 0x01 = JS_EVENT_BUTTON; se ignoran los eventos de estado inicial (0x80) */
                    if (e.value) { if (pressed_at < 0) pressed_at = now_ms(); }
                    else pressed_at = -1;
                }
            }
        } else if (r > 0 && (pfd.revents & (POLLERR | POLLHUP))) {
            return 1;                                                  /* el dispositivo desaparecio */
        }
        if (pressed_at >= 0 && now_ms() - pressed_at >= hold) {
            printf("[menuquit] boton %d mantenido: cerrando el proceso %d (SIGTERM)\n", button, (int)pid); fflush(stdout);
            kill(pid, SIGTERM);
            for (int i = 0; i < 30 && alive(pid); i++) usleep(100000);
            if (alive(pid)) { printf("[menuquit] sigue vivo: SIGKILL\n"); fflush(stdout); kill(pid, SIGKILL); }
            return 0;
        }
    }
}
