import Foundation

/// One running copy per user, enforced with an advisory `flock`. A second launch
/// pings the first over a distributed notification and exits.
final class SingleInstance {
    static let activateNotification = Notification.Name("com.rutamt.lofihud.activate")
    private var fd: Int32 = -1

    func acquire() -> Bool {
        fd = open(Paths.lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return true }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            fd = -1
            return false
        }
        return true
    }

    func notifyRunningInstance() {
        DistributedNotificationCenter.default().postNotificationName(
            Self.activateNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }

    func listen(_ handler: @escaping () -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: Self.activateNotification, object: nil, queue: .main) { _ in handler() }
    }

    func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }
}
