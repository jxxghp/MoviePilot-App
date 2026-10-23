import UIKit

/// 保留系统横向菜单及玻璃动画，将展开生命周期交给宿主协调标题可见性。
@MainActor
final class HeaderActionsButton: UIButton {
  var onMenuVisibilityChange: ((Bool) -> Void)?

  /// 展开操作区时暂隐其后方标题，避免透明菜单内透出重叠文字。
  override func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    willDisplayMenuFor configuration: UIContextMenuConfiguration,
    animator: (any UIContextMenuInteractionAnimating)?
  ) {
    super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
    onMenuVisibilityChange?(true)
  }

  /// 系统菜单完全收起后恢复当前标题，业务导航可能已在菜单动作中改变。
  override func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    willEndFor configuration: UIContextMenuConfiguration,
    animator: (any UIContextMenuInteractionAnimating)?
  ) {
    super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
    if let animator {
      animator.addCompletion { [weak self] in self?.onMenuVisibilityChange?(false) }
    } else {
      onMenuVisibilityChange?(false)
    }
  }
}
