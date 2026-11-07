/* /usr/sbin/poweroff for the guest: the Docker image has no init system, so call reboot(2) directly */
#include <stdio.h>
#include <sys/reboot.h>
#include <unistd.h>

int main(void) {
  sync();
  reboot(RB_POWER_OFF);
  perror("reboot");
  return 1;
}
