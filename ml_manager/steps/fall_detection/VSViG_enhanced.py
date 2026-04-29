"""
VSViG_enhanced.py - Enhanced VSViG with restored core graph reasoning
plus global patches, kinematic features, and attention-based multi-modal fusion.

Core architecture (InterPartMR, IntraPartMR, Grapher, Part_3DCNN, Stem, Stem_pe)
is faithfully restored from the original ECCV 2024 VSViG paper.  Enhancements
(GlobalPatchStem, KinematicFeatureMLP, TemporalFeatureFusion, MultiModalFusion)
are layered on top without altering the original local-patch processing path.
"""

import warnings
import os
import torch
import torch.nn as nn
import torch.nn.functional as F
import numpy as np
from torchvision.models import resnet18, ResNet18_Weights
from timm.models.registry import register_model


# ============================================================================
# Original VSViG Core Components - faithfully restored from VSViG.py (ECCV 2024)
# ============================================================================

class InterPartMR(nn.Module):
    """Inter-part message reasoning.

    Builds a full PxP pairwise difference matrix, then for each of the 5 body
    parts masks out same-part interactions (-1e4) and takes max over the
    remaining connections to aggregate inter-part messages.
    """

    def __init__(self, out_channels):
        super().__init__()
        self.nn = nn.Sequential(
            nn.Conv2d(out_channels * 2, out_channels * 2, 1, groups=4),
            nn.BatchNorm2d(out_channels * 2),
            nn.ReLU(),
        )

    def forward(self, x):
        B, C, P, _ = x.shape  # BxT, C, P, 1
        tmp_x = x.clone()
        x_i = x.repeat(1, 1, 1, P)  # BxT, C, P, P
        x_j = x_i.clone()
        for k in range(P):
            x_j[:, :, :, k] = x_i[:, :, k, k].unsqueeze(-1).repeat(1, 1, P)
        relative = x_j - x_i
        for part in range(5):
            tmp_relative = relative.clone()
            tmp_relative[:, :, :, part * 3:(part + 1) * 3] = (
                relative[:, :, :, part * 3:(part + 1) * 3] - 1e4
            )
            tmp_x_j, _ = torch.max(tmp_relative, -1, keepdim=True)
            tmp_x[:, :, part * 3:(part + 1) * 3, :] = (
                tmp_x_j[:, :, part * 3:(part + 1) * 3, :]
            )
        x = torch.cat([x, tmp_x], 1)
        return self.nn(x)


class IntraPartMR(nn.Module):
    """Intra-part message reasoning.

    Builds a full PxP pairwise difference matrix, then for each point takes
    max only over its own 3-node body-part group.
    """

    def __init__(self, out_channels):
        super().__init__()
        self.nn = nn.Sequential(
            nn.Conv2d(out_channels * 2, out_channels * 2, 1, groups=4),
            nn.BatchNorm2d(out_channels * 2),
            nn.ReLU(),
        )

    def forward(self, x):
        B, C, P, _ = x.shape  # BxT, C, P, 1
        tmp_x = x.clone()
        x_i = x.repeat(1, 1, 1, P)  # BxT, C, P, P
        x_j = x_i.clone()
        for k in range(P):
            x_j[:, :, :, k] = x_i[:, :, k, k].unsqueeze(-1).repeat(1, 1, P)
        relative = x_j - x_i  # BxT, C, P, P
        part = 1
        for point in range(P):
            tmp_x_j, _ = torch.max(
                relative[:, :, point, (part - 1) * 3 + 1:part * 3 + 1],
                -1, keepdim=True,
            )
            tmp_x[:, :, point, :] = tmp_x_j
            if (point + 1) % 3 == 0:
                part = 1 + part
        x = torch.cat([x, tmp_x], 1)
        return self.nn(x)


class Stem(nn.Module):
    """Patch-to-token stem.

    A single Conv2d with kernel_size=patch_size and stride=patch_size collapses
    each 32x32 patch into a single feature vector.  Output is 4-D: (B, T, P, C).
    """

    def __init__(self, input_dim=3, output_dim=None, patch_size=32):
        super().__init__()
        self.stem = nn.Sequential(
            nn.Conv2d(input_dim, output_dim, kernel_size=patch_size, stride=patch_size),
            nn.BatchNorm2d(output_dim),
        )

    def forward(self, x):
        B, T, P, C, H, W = x.shape
        x = x.view(-1, C, H, W)
        x = self.stem(x)  # (B*T*P, C_out, 1, 1)
        x = x.view(B, T, P, x.shape[1])  # (B, T, P, C_out)
        return x


class Stem_pe(nn.Module):
    """Positional-embedding stem for keypoint coordinates.

    Projects (x, y, conf) through a 1x1 Conv2d + BatchNorm2d.
    """

    def __init__(self, input_dim=3, output_dim=None, patch_size=32):
        super().__init__()
        self.stem = nn.Sequential(
            nn.Conv2d(input_dim, output_dim, kernel_size=1, stride=1),
            nn.BatchNorm2d(output_dim),
        )

    def forward(self, x):
        B, T, P, C = x.shape
        x = x.view(-1, C, 1, 1)
        x = self.stem(x)  # (B*T*P, C_out, 1, 1)
        x = x.view(B, T, P, x.shape[1])  # (B, T, P, C_out)
        return x


class Grapher(nn.Module):
    """Two-stage graph reasoning: Inter-part -> residual -> Intra-part -> residual.

    Output preserves in_channels (identity residual design).
    """

    def __init__(self, in_channels, out_channels):
        super().__init__()
        self.fc1 = nn.Sequential(
            nn.Conv2d(in_channels, out_channels, 1, stride=1, padding=0),
            nn.BatchNorm2d(out_channels),
        )
        self.fc2 = nn.Sequential(
            nn.Conv2d(out_channels * 2, in_channels, 1, stride=1, padding=0),
            nn.BatchNorm2d(in_channels),
        )
        self.fc3 = nn.Sequential(
            nn.Conv2d(in_channels, out_channels, 1, stride=1, padding=0),
            nn.BatchNorm2d(out_channels),
        )
        self.fc4 = nn.Sequential(
            nn.Conv2d(out_channels * 2, in_channels, 1, stride=1, padding=0),
            nn.BatchNorm2d(in_channels),
        )
        self.InterPartMR = InterPartMR(out_channels)
        self.IntraPartMR = IntraPartMR(out_channels)
        self.act = nn.ReLU()
        self.dropout = nn.Dropout(p=0.5)

    def forward(self, x):
        B, T, C, P, _ = x.shape  # (B, T, C, P, 1)
        x = x.view(-1, C, P, 1)  # (B*T, C, P, 1)
        tmp_x = x
        # Stage 1: Inter-part
        x = self.fc1(x)
        x = self.InterPartMR(x)
        x = self.fc2(x)
        x = x + tmp_x
        x = self.act(x)
        # Stage 2: Intra-part
        x = self.fc3(x)
        x = self.IntraPartMR(x)
        x = self.fc4(x)
        x = x + tmp_x
        x = self.act(x)
        return x.view(B, T, C, P, 1)


class Part_3DCNN(nn.Module):
    """Three-stage bottleneck 3D CNN with (3,3,1) spatiotemporal kernel
    and dynamic partition reordering.
    """

    def __init__(self, in_channels, out_channels, stride=1, dynamic=False,
                 dynamic_point_order=None, SEED=None, expansion=4):
        super().__init__()
        self.expansion = expansion
        self.conv1 = nn.Sequential(
            nn.Conv3d(in_channels, out_channels, kernel_size=1),
            nn.BatchNorm3d(out_channels),
            nn.ReLU(),
        )
        self.conv2 = nn.Sequential(
            nn.Conv3d(out_channels, out_channels, kernel_size=(3, 3, 1),
                      stride=stride, padding=1, padding_mode='replicate'),
            nn.BatchNorm3d(out_channels),
            nn.ReLU(),
        )
        self.conv3 = nn.Sequential(
            nn.Conv3d(out_channels, out_channels * self.expansion, 1),
            nn.BatchNorm3d(out_channels * self.expansion),
            nn.ReLU(),
        )
        self.downsample = nn.Sequential(
            nn.Conv3d(in_channels, out_channels * self.expansion, 1, stride=stride),
            nn.BatchNorm3d(out_channels * self.expansion),
        )
        self.dynamic = dynamic
        self.dynamic_point_order = dynamic_point_order
        self.act = nn.ReLU()
        self.stride = stride
        self.in_ = in_channels
        self.SEED = SEED

    def dynamic_trans(self, x):
        B, C, T, P, _ = x.shape
        x = x.view(-1, P)
        dynamic_order = self.dynamic_point_order[self.SEED]
        raw_order = list(np.arange(15))
        x[:, raw_order] = x[:, dynamic_order]
        return x.view(B, C, T, P, 1)

    def forward(self, x):
        B, T, C, P, _ = x.shape
        x = x.transpose(1, 2).contiguous()  # (B, C, T, P, 1)
        if self.dynamic:
            x = self.dynamic_trans(x)
        residual = x
        x = self.conv1(x)
        x = self.conv2(x)
        x = x[:, :, :, :, 1].unsqueeze(-1)  # center slice
        x = self.conv3(x)
        residual = self.downsample(residual)
        x = residual + x
        x = self.act(x)
        return x.transpose(1, 2).contiguous()


# ============================================================================
# Enhanced Multi-Modal Components
# ============================================================================

class GlobalPatchStem(nn.Module):
    """ResNet18-based encoder for full-body crops with optional motion channel."""

    def __init__(self, pretrained=True, trainable=True, use_motion=True):
        super().__init__()
        self.use_motion = use_motion

        weights = ResNet18_Weights.IMAGENET1K_V1 if pretrained else None
        backbone = None
        if pretrained:
            try:
                backbone = resnet18(weights=weights)
            except TypeError:
                backbone = resnet18(pretrained=True)
            except Exception as err:
                warnings.warn(f"Falling back to random ResNet18: {err}", RuntimeWarning)
                pretrained = False
        if backbone is None:
            try:
                backbone = resnet18(weights=None)
            except TypeError:
                backbone = resnet18(pretrained=False)

        input_channels = 6 if self.use_motion else 3
        original_conv1 = backbone.conv1
        if original_conv1.in_channels != input_channels:
            new_conv1 = nn.Conv2d(
                in_channels=input_channels,
                out_channels=original_conv1.out_channels,
                kernel_size=original_conv1.kernel_size,
                stride=original_conv1.stride,
                padding=original_conv1.padding,
                bias=original_conv1.bias is not None,
            )
            with torch.no_grad():
                new_conv1.weight[:, :3, :, :] = original_conv1.weight
                if input_channels > 3:
                    extra = input_channels - 3
                    template = original_conv1.weight.mean(dim=1, keepdim=True).repeat(1, extra, 1, 1)
                    new_conv1.weight[:, 3:, :, :] = template
                if original_conv1.bias is not None:
                    new_conv1.bias.copy_(original_conv1.bias)
            backbone.conv1 = new_conv1

        self.backbone = nn.Sequential(
            backbone.conv1, backbone.bn1, backbone.relu, backbone.maxpool,
            backbone.layer1, backbone.layer2, backbone.layer3, backbone.layer4,
            backbone.avgpool,
        )
        self.feature_dim = backbone.fc.in_features  # 512

        if not trainable:
            for param in self.backbone.parameters():
                param.requires_grad = False

        for module in self.backbone.modules():
            setattr(module, "_skip_init", True)

        mean_ch = [0.485, 0.456, 0.406]
        std_ch = [0.229, 0.224, 0.225]
        if self.use_motion:
            mean_ch.extend([0.0, 0.0, 0.0])
            std_ch.extend([1.0, 1.0, 1.0])
        self.register_buffer("imagenet_mean",
                             torch.tensor(mean_ch).float().view(1, len(mean_ch), 1, 1))
        self.register_buffer("imagenet_std",
                             torch.tensor(std_ch).float().view(1, len(std_ch), 1, 1))

    def forward(self, x):
        if x is None:
            raise ValueError("Global patches tensor is None")
        x = x.to(dtype=torch.float32)
        B, T, H, W, _ = x.shape
        if torch.amax(x) > 1.0 and torch.amin(x) >= 0.0:
            x = x / 255.0
        rgb = x
        if self.use_motion:
            motion = torch.zeros_like(rgb)
            motion[:, 1:] = rgb[:, 1:] - rgb[:, :-1]
            motion = motion.clamp_(-1.0, 1.0)
            x = torch.cat([rgb, motion], dim=-1)
        _, _, _, _, nc = x.shape
        x = x.permute(0, 1, 4, 2, 3).reshape(-1, nc, H, W)
        x = (x - self.imagenet_mean) / self.imagenet_std
        x = self.backbone(x).flatten(1)
        return x.view(B, T, -1)


class KinematicFeatureMLP(nn.Module):
    """MLP for processing kinematic feature vectors."""

    def __init__(self, input_dim, output_dim, hidden_dims=None):
        super().__init__()
        if hidden_dims is None:
            hidden_dims = [128, 64]
        layers = []
        prev = input_dim
        for h in hidden_dims:
            layers.extend([nn.Linear(prev, h), nn.BatchNorm1d(h), nn.ReLU(), nn.Dropout(0.2)])
            prev = h
        layers.append(nn.Linear(prev, output_dim))
        self.mlp = nn.Sequential(*layers)

    def forward(self, x):
        return self.mlp(x)


class TemporalFeatureFusion(nn.Module):
    """Multi-head attention over the temporal dimension."""

    def __init__(self, feature_dim):
        super().__init__()
        self.attention = nn.MultiheadAttention(feature_dim, num_heads=8, batch_first=True)
        self.norm = nn.LayerNorm(feature_dim)
        self.dropout = nn.Dropout(0.1)

    def forward(self, x):
        attn_out, _ = self.attention(x, x, x)
        return self.norm(x + self.dropout(attn_out))


class MultiModalFusion(nn.Module):
    """Attention-based fusion of local, global, and kinematic features."""

    def __init__(self, local_dim, global_dim, kinematic_dim, output_dim):
        super().__init__()
        self.local_proj = nn.Linear(local_dim, output_dim)
        self.global_proj = nn.Linear(global_dim, output_dim)
        self.kinematic_proj = nn.Linear(kinematic_dim, output_dim)
        self.fusion_attention = nn.MultiheadAttention(output_dim, num_heads=4, batch_first=True)
        self.norm = nn.LayerNorm(output_dim)
        self.dropout = nn.Dropout(0.2)
        self.final_proj = nn.Sequential(
            nn.Linear(output_dim, output_dim), nn.ReLU(),
            nn.Dropout(0.2), nn.Linear(output_dim, output_dim),
        )

    def forward(self, local_features, global_features, kinematic_features):
        local_proj = self.local_proj(local_features)
        global_proj = self.global_proj(global_features)
        kinematic_proj = self.kinematic_proj(kinematic_features)
        multi_modal = torch.stack([local_proj, global_proj, kinematic_proj], dim=1)
        fused, attention_weights = self.fusion_attention(multi_modal, multi_modal, multi_modal)
        fused = self.norm(multi_modal + self.dropout(fused))
        fused = torch.mean(fused, dim=1)
        return self.final_proj(fused), attention_weights


# ============================================================================
# Enhanced STViG - original core + multi-modal enhancements
# ============================================================================

class EnhancedSTViG(nn.Module):
    """Enhanced STViG with faithfully restored graph reasoning core and
    optional multi-modal branches (global patches, kinematic features).
    """

    def __init__(self, opt, kinematic_feature_dim=25,
                 use_global_patches=True, use_kinematic_features=True):
        super().__init__()
        self.use_global_patches = use_global_patches
        self.use_kinematic_features = use_kinematic_features

        dynamic = opt.dynamic
        num_layer = opt.num_layer
        output_channels = opt.output_channels
        dynamic_point_order = opt.dynamic_point_order
        expansion = opt.expansion
        self.pos_emb = opt.pos_emb

        if opt.pos_emb == 'add':
            ch4stem = output_channels[0] - 3
        else:
            ch4stem = output_channels[0]

        # Original VSViG local-patch path
        self.stem = Stem(input_dim=3, output_dim=ch4stem)
        self.stem_pe = Stem_pe(input_dim=3, output_dim=ch4stem)

        # Build backbone exactly as original STViG
        self.in_channels = output_channels[0]
        self.backbone = []
        for stage in range(len(num_layer)):
            if stage > 0:
                self.backbone.append(
                    Grapher(in_channels=self.in_channels,
                            out_channels=output_channels[stage]))
                self.backbone.append(
                    Part_3DCNN(stride=(2, 1, 1),
                               in_channels=self.in_channels,
                               out_channels=output_channels[stage],
                               dynamic=dynamic,
                               dynamic_point_order=dynamic_point_order,
                               expansion=expansion,
                               SEED=stage * num_layer[stage] + layers))
                self.in_channels = output_channels[stage] * expansion

            for layers in range(num_layer[stage]):
                self.backbone.append(
                    Grapher(in_channels=self.in_channels,
                            out_channels=output_channels[stage]))
                self.backbone.append(
                    Part_3DCNN(in_channels=self.in_channels,
                               out_channels=output_channels[stage],
                               dynamic=dynamic,
                               dynamic_point_order=dynamic_point_order,
                               expansion=expansion,
                               SEED=stage * num_layer[stage] + layers))
                if stage == 0:
                    self.in_channels = output_channels[stage] * expansion

        self.backbone = nn.Sequential(*self.backbone)

        local_feature_dim = output_channels[-1] * expansion

        # Enhanced multi-modal branches
        if self.use_global_patches:
            self.global_stem = GlobalPatchStem()
            self.global_feature_dim = self.global_stem.feature_dim
            self.global_temporal_fusion = TemporalFeatureFusion(self.global_feature_dim)
        else:
            self.global_feature_dim = 1

        if self.use_kinematic_features:
            self.kinematic_mlp = KinematicFeatureMLP(
                input_dim=kinematic_feature_dim, output_dim=64)
            self.kinematic_feature_dim_out = 64
        else:
            self.kinematic_feature_dim_out = 1

        # Classifier
        if self.use_global_patches or self.use_kinematic_features:
            fusion_dim = 256
            self.multi_modal_fusion = MultiModalFusion(
                local_dim=local_feature_dim,
                global_dim=self.global_feature_dim if self.use_global_patches else 1,
                kinematic_dim=self.kinematic_feature_dim_out if self.use_kinematic_features else 1,
                output_dim=fusion_dim,
            )
            self.classifier = nn.Sequential(
                nn.Linear(fusion_dim, 256), nn.BatchNorm1d(256), nn.ReLU(), nn.Dropout(0.3),
                nn.Linear(256, 128), nn.BatchNorm1d(128), nn.ReLU(), nn.Dropout(0.2),
                nn.Linear(128, 1),
            )
        else:
            self.fc = nn.Sequential(
                nn.Conv2d(local_feature_dim, 256, 1),
                nn.BatchNorm2d(256), nn.ReLU(),
                nn.Conv2d(256, 1, 1),
            )

        self.model_init()

    def model_init(self):
        for m in self.modules():
            if getattr(m, "_skip_init", False):
                continue
            if isinstance(m, (nn.Conv3d, nn.Conv2d)):
                nn.init.kaiming_normal_(m.weight)
                m.weight.requires_grad = True
                if m.bias is not None:
                    m.bias.data.zero_()
                    m.bias.requires_grad = True
            elif isinstance(m, (nn.BatchNorm2d, nn.BatchNorm3d, nn.BatchNorm1d)):
                nn.init.constant_(m.bias, 0.0)
                nn.init.constant_(m.weight, 1.0)
            elif isinstance(m, nn.Linear):
                nn.init.xavier_normal_(m.weight)
                if m.bias is not None:
                    nn.init.constant_(m.bias, 0.0)

    def pe(self, flag, x, kpts=None):
        B, T, P, C = x.shape
        if flag == 'learn':
            x = x + nn.Parameter(torch.zeros(1, T, P, C)).cuda()
        elif flag == 'add':
            x = torch.cat((x, kpts), axis=-1)
        elif flag == 'stem':
            pe = self.stem_pe(kpts)
            x = x + pe
        elif flag == 'no':
            x = x
        return x

    def forward(self, local_patches, keypoints=None,
                global_patches=None, kinematic_features=None,
                return_logits=False):
        """
        Args:
            local_patches:      (B, T, P, C, H, W) - (B, 30, 15, 3, 32, 32)
            keypoints:          (B, T, P, 3) - (B, 30, 15, 3)
            global_patches:     (B, T, H, W, 3) - (B, 30, 64, 64, 3)
            kinematic_features: (B, D) - (B, 25)
            return_logits:      if True, return raw logits instead of sigmoid
        Returns:
            (output, attention_weights) tuple.
        """
        # 1) Local patch backbone (original VSViG path)
        x = self.stem(local_patches)  # (B, T, P, C_stem) - 4D
        x = self.pe(self.pos_emb, x, keypoints)
        B, T, P, C = x.shape
        x = x.transpose(2, 3).contiguous().view(B, T, C, P, 1)
        x = self.backbone(x)
        B, T, C, P, _ = x.shape
        x = x.transpose(1, 2).contiguous().view(B, C, T, P)
        local_features = F.adaptive_avg_pool2d(x, 1).squeeze(-1).squeeze(-1)  # (B, C)

        # 2) Multi-modal path
        if self.use_global_patches or self.use_kinematic_features:
            if self.use_global_patches and global_patches is not None:
                gf = self.global_stem(global_patches)
                gf = self.global_temporal_fusion(gf)
                global_feat = torch.mean(gf, dim=1)
            else:
                global_feat = torch.zeros(
                    B, self.global_feature_dim,
                    device=local_features.device, dtype=local_features.dtype)

            if self.use_kinematic_features and kinematic_features is not None:
                kin_feat = self.kinematic_mlp(kinematic_features)
            else:
                kin_feat = torch.zeros(
                    B, self.kinematic_feature_dim_out,
                    device=local_features.device, dtype=local_features.dtype)

            fused, attn_w = self.multi_modal_fusion(local_features, global_feat, kin_feat)
            logits = self.classifier(fused).squeeze(-1)
            if return_logits:
                return logits, attn_w
            return torch.sigmoid(logits), attn_w
        else:
            logits = self.fc(
                local_features.unsqueeze(-1).unsqueeze(-1)
            ).squeeze(-1).squeeze(-1).squeeze(-1)
            if return_logits:
                return logits, None
            return torch.sigmoid(logits), None


# ============================================================================
# Model factory functions
# ============================================================================

def _load_dynamic_point_order():
    """Try to load the dynamic point order file."""
    search_paths = [
        'dy_point_order.pt',
        os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dy_point_order.pt'),
        'VSViG/dy_point_order.pt',
    ]
    for p in search_paths:
        if os.path.exists(p):
            try:
                return torch.load(p, weights_only=True)
            except TypeError:
                return torch.load(p)
    warnings.warn("dy_point_order.pt not found - using identity permutations", RuntimeWarning)
    return {i: list(range(15)) for i in range(50)}


@register_model
def EnhancedVSViG_base(pretrained=False, kinematic_feature_dim=25,
                        use_global_patches=True, use_kinematic_features=True, **kwargs):
    """Enhanced VSViG base model."""
    class OptInit:
        def __init__(self, **kw):
            self.dynamic = 1
            self.num_layer = [2, 2, 6, 2]
            self.output_channels = [24, 48, 96, 192]
            self.dynamic_point_order = _load_dynamic_point_order()
            self.expansion = 2
            self.pos_emb = 'stem'
    opt = OptInit(**kwargs)
    return EnhancedSTViG(opt, kinematic_feature_dim, use_global_patches, use_kinematic_features)


@register_model
def EnhancedVSViG_light(pretrained=False, kinematic_feature_dim=25,
                         use_global_patches=True, use_kinematic_features=True, **kwargs):
    """Enhanced VSViG light model."""
    class OptInit:
        def __init__(self, **kw):
            self.dynamic = 1
            self.num_layer = [2, 2, 6, 2]
            self.output_channels = [12, 24, 48, 96]
            self.dynamic_point_order = _load_dynamic_point_order()
            self.expansion = 2
            self.pos_emb = 'stem'
    opt = OptInit(**kwargs)
    return EnhancedSTViG(opt, kinematic_feature_dim, use_global_patches, use_kinematic_features)


# ============================================================================
# Quick smoke test
# ============================================================================

if __name__ == "__main__":
    print("Testing Enhanced VSViG (restored core)...")

    model_base = EnhancedVSViG_base()
    model_light = EnhancedVSViG_light()

    n_base = sum(p.numel() for p in model_base.parameters())
    n_light = sum(p.numel() for p in model_light.parameters())
    print(f"  Base model:  {n_base:,} parameters")
    print(f"  Light model: {n_light:,} parameters")

    B, T, P = 2, 30, 15
    local_patches = torch.randn(B, T, P, 3, 32, 32)
    keypoints = torch.randn(B, T, P, 3)
    global_patches = torch.randn(B, T, 64, 64, 3)
    kinematic_features = torch.randn(B, 25)

    try:
        with torch.no_grad():
            out_b, attn_b = model_base(local_patches, keypoints,
                                        global_patches, kinematic_features)
            out_l, attn_l = model_light(local_patches, keypoints,
                                         global_patches, kinematic_features)
        print(f"  Base output:  {out_b.shape} - values: {out_b}")
        print(f"  Light output: {out_l.shape} - values: {out_l}")

        model_orig = EnhancedVSViG_base(use_global_patches=False,
                                         use_kinematic_features=False)
        with torch.no_grad():
            out_o, _ = model_orig(local_patches, keypoints)
        print(f"  Original-only output: {out_o.shape} - values: {out_o}")

        print("  All tests passed!")
    except Exception as e:
        print(f"  Test FAILED: {e}")
        import traceback
        traceback.print_exc()
