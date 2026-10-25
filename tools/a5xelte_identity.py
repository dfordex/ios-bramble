"""One iOS product identity for the A5XELTE device tree and BOOT packer.

Apple product/board names describe the selected userland compatibility model;
Samsung compatibles continue to select the actual Exynos hardware drivers.
"""
import adt

PRODUCT_TYPE = 'iPhone10,5'
BOARD_TYPE = 'D211AP'
TARGET_TYPE = 'D211'


def apply(root):
    properties = {
        'model': PRODUCT_TYPE.encode() + b'\0',
        'compatible': (BOARD_TYPE.encode() + b'\0' + PRODUCT_TYPE.encode() +
                       b'\0samsung,a5xelte\0samsung,exynos7580\0AppleARM\0'),
        'target-type': TARGET_TYPE.encode() + b'\0',
        'target-sub-type': BOARD_TYPE.encode() + b'\0',
    }
    for name, value in properties.items():
        matches = [i for i, (key, _, _) in enumerate(root.props) if key == name]
        if len(matches) != 1:
            raise ValueError('missing or duplicate root identity: ' + name)
        root.props[matches[0]] = (name, 0, value)
    return root


def rewrite(blob):
    root, end = adt.parse(blob)
    if end != len(blob) or root.name != 'device-tree':
        raise ValueError('identity requires a complete device tree')
    compatible = root.prop('compatible').split(b'\0')
    if b'samsung,a5xelte' not in compatible or b'samsung,exynos7580' not in compatible:
        raise ValueError('identity rewrite requires the A5XELTE hardware tree')
    return adt.serialize(apply(root))
