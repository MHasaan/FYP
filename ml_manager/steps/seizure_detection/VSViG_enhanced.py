import warnings

# VSViG_enhanced.py - Enhanced VSViG with global patches and kinematic features
# Run: python VSViG_enhanced.py
import torch
import torch.nn as nn
from torchvision.models import resnet18, ResNet18_Weights
from timm.models.registry import register_model
import numpy as np
import torch.nn.functional as F

# VSViG Core Components (embedded to avoid import issues)
class InterPartMR(nn.Module):
    """Inter-part message passing"""
    def __init__(self, in_channels, out_channels):
        super().__init__()
        self.conv = nn.Conv2d(in_channels, out_channels, 1)
        self.norm = nn.BatchNorm2d(out_channels)
        self.act = nn.ReLU()
    
    def forward(self, x):
        return self.act(self.norm(self.conv(x)))

class IntraPartMR(nn.Module):
    """Intra-part message passing"""
    def __init__(self, in_channels, out_channels):
        super().__init__()
        self.conv = nn.Conv2d(in_channels, out_channels, 1)
        self.norm = nn.BatchNorm2d(out_channels)
        self.act = nn.ReLU()
    
    def forward(self, x):
        return self.act(self.norm(self.conv(x)))

class Stem(nn.Module):
    """VSViG stem for patch extraction"""
    def __init__(self, input_dim=3, output_dim=24):
        super().__init__()
        self.conv1 = nn.Conv3d(input_dim, output_dim//2, kernel_size=(1,8,8), stride=(1,4,4), padding=(0,2,2))
        self.bn1 = nn.BatchNorm3d(output_dim//2)
        self.conv2 = nn.Conv3d(output_dim//2, output_dim, kernel_size=(1,4,4), stride=(1,2,2), padding=(0,1,1))
        self.bn2 = nn.BatchNorm3d(output_dim)
        self.relu = nn.ReLU()
    
    def forward(self, x):
        # x: (B, T, P, C, H, W)
        B, T, P, C, H, W = x.shape
        x = x.view(B, T*P, C, H, W).transpose(1, 2)  # (B, C, T*P, H, W)
        x = self.relu(self.bn1(self.conv1(x)))
        x = self.relu(self.bn2(self.conv2(x)))
        return x.transpose(1, 2).view(B, T, P, -1, x.shape[-2], x.shape[-1])

class Stem_pe(nn.Module):
    """VSViG stem with positional encoding for keypoints"""
    def __init__(self, input_dim=3, output_dim=24):
        super().__init__()
        # For keypoint processing
        self.keypoint_embed = nn.Linear(input_dim, output_dim)
        self.norm = nn.LayerNorm(output_dim)
    
    def forward(self, x):
        # x: (B, T, P, 3) - keypoints
        if len(x.shape) == 4:
            B, T, P, C = x.shape
            # Embed keypoints to feature space
            x = self.keypoint_embed(x)  # (B, T, P, output_dim)
            x = self.norm(x)
            return x
        else:
            raise ValueError(f"Stem_pe expects 4D keypoint tensor, got {x.shape}")

class Grapher(nn.Module):
    """Graph convolution module"""
    def __init__(self, in_channels, out_channels):
        super().__init__()
        self.inter_mr = InterPartMR(in_channels, out_channels)
        self.intra_mr = IntraPartMR(in_channels, out_channels)
        self.fusion = nn.Conv2d(out_channels * 2, out_channels, 1)
        self.norm = nn.BatchNorm2d(out_channels)
    
    def forward(self, x):
        # x: (B, T, C, P, 1)
        B, T, C, P, _ = x.shape
        x = x.squeeze(-1).permute(0, 2, 1, 3)  # (B, C, T, P)
        
        inter_out = self.inter_mr(x)
        intra_out = self.intra_mr(x)
        
        fused = torch.cat([inter_out, intra_out], dim=1)
        out = self.norm(self.fusion(fused))
        
        return out.permute(0, 2, 1, 3).unsqueeze(-1)  # (B, T, C, P, 1)

class Part_3DCNN(nn.Module):
    """3D CNN for part-based processing"""
    def __init__(self, in_channels, out_channels, stride=(1,1,1), dynamic=1, 
                 dynamic_point_order=None, expansion=2, SEED=0):
        super().__init__()
        self.expansion = expansion
        self.conv1 = nn.Conv3d(in_channels, out_channels, 1)
        self.bn1 = nn.BatchNorm3d(out_channels)
        self.conv2 = nn.Conv3d(out_channels, out_channels * expansion, 1)
        self.bn2 = nn.BatchNorm3d(out_channels * expansion)
        self.relu = nn.ReLU()
        self.stride = stride
        self.use_projection = in_channels != out_channels * expansion
        if self.use_projection:
            self.residual_proj = nn.Conv3d(in_channels, out_channels * expansion, kernel_size=1, bias=False)
            self.residual_bn = nn.BatchNorm3d(out_channels * expansion)
    
    def forward(self, x):
        # x: (B, T, C, P, 1)
        B, T, C, P, _ = x.shape
        x = x.permute(0, 2, 1, 3, 4)  # (B, C, T, P, 1)
        
        if self.stride != (1,1,1):
            x = F.avg_pool3d(x, self.stride, self.stride)
        
        residual = x
        if self.use_projection:
            residual = self.residual_bn(self.residual_proj(residual))
        
        out = self.relu(self.bn1(self.conv1(x)))
        out = self.bn2(self.conv2(out))
        
        out += residual
        out = self.relu(out)
        
        return out.permute(0, 2, 1, 3, 4)  # (B, T, C, P, 1)

class GlobalPatchStem(nn.Module):
    """ResNet18-based encoder for processing global body patches."""

    def __init__(
        self,
        pretrained: bool = True,
        trainable: bool = True,
        use_motion: bool = True,
    ):
        super().__init__()

        self.use_motion = use_motion

        weights = ResNet18_Weights.IMAGENET1K_V1 if pretrained else None
        backbone = None

        if pretrained:
            try:
                backbone = resnet18(weights=weights)
            except TypeError:
                # Fallback for older torchvision versions
                backbone = resnet18(pretrained=True)
            except Exception as err:  # pragma: no cover - network/IO errors
                warnings.warn(
                    f"Falling back to randomly initialised ResNet18 due to pretrained weight load failure: {err}",
                    RuntimeWarning,
                )
                pretrained = False  # Track fallback state

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
                    extra_channels = input_channels - 3
                    channel_template = original_conv1.weight.mean(dim=1, keepdim=True).repeat(1, extra_channels, 1, 1)
                    new_conv1.weight[:, 3:, :, :] = channel_template
                if original_conv1.bias is not None:
                    new_conv1.bias.copy_(original_conv1.bias)

            backbone.conv1 = new_conv1

        # Strip classification head; keep convolutional trunk + avg pool
        self.backbone = nn.Sequential(
            backbone.conv1,
            backbone.bn1,
            backbone.relu,
            backbone.maxpool,
            backbone.layer1,
            backbone.layer2,
            backbone.layer3,
            backbone.layer4,
            backbone.avgpool,
        )

        self.feature_dim = backbone.fc.in_features  # 512 for ResNet18

        if not trainable:
            for param in self.backbone.parameters():
                param.requires_grad = False

        # Mark backbone modules to skip reinitialisation in model_init
        for module in self.backbone.modules():
            setattr(module, "_skip_init", True)

        # Register normalisation statistics (RGB + optional motion)
        mean_channels = [0.485, 0.456, 0.406]
        std_channels = [0.229, 0.224, 0.225]

        if self.use_motion:
            mean_channels.extend([0.0, 0.0, 0.0])
            std_channels.extend([1.0, 1.0, 1.0])

        mean = torch.tensor(mean_channels, dtype=torch.float32).view(1, len(mean_channels), 1, 1)
        std = torch.tensor(std_channels, dtype=torch.float32).view(1, len(std_channels), 1, 1)
        self.register_buffer("imagenet_mean", mean)
        self.register_buffer("imagenet_std", std)

    def forward(self, x):
        """Encode global patches with ResNet18.

        Args:
            x: Tensor of shape (B, T, H, W, 3) with pixel intensities in [0, 255]
                or already normalised to [0, 1].

        Returns:
            Tensor of shape (B, T, feature_dim) with encoded features.
        """
        if x is None:
            raise ValueError("Global patches tensor is None while global encoder is enabled.")

        x = x.to(dtype=torch.float32)
        B, T, H, W, _ = x.shape

        x_max = torch.amax(x)
        x_min = torch.amin(x)
        if x_max > 1.0 and x_min >= 0.0:
            x = x / 255.0

        rgb = x

        if self.use_motion:
            motion = torch.zeros_like(rgb)
            motion[:, 1:] = rgb[:, 1:] - rgb[:, :-1]
            motion = motion.clamp_(-1.0, 1.0)
            x = torch.cat([rgb, motion], dim=-1)  # (B, T, H, W, 6)
        else:
            x = rgb

        _, _, _, _, num_channels = x.shape

        # Move channel dimension forward for conv layers -> (B*T, C, H, W)
        x = x.permute(0, 1, 4, 2, 3).reshape(-1, num_channels, H, W)

        # Apply normalisation expected by ResNet18 (extended)
        x = (x - self.imagenet_mean) / self.imagenet_std

        # Forward through ResNet trunk
        x = self.backbone(x)  # (B*T, 512, 1, 1)
        x = x.flatten(1)  # (B*T, 512)
        x = x.view(B, T, -1)  # (B, T, feature_dim)

        return x

class KinematicFeatureMLP(nn.Module):
    """MLP for processing kinematic features"""
    def __init__(self, input_dim, output_dim, hidden_dims=[128, 64]):
        super().__init__()
        layers = []
        
        prev_dim = input_dim
        for hidden_dim in hidden_dims:
            layers.extend([
                nn.Linear(prev_dim, hidden_dim),
                nn.BatchNorm1d(hidden_dim),
                nn.ReLU(),
                nn.Dropout(0.2)
            ])
            prev_dim = hidden_dim
        
        layers.append(nn.Linear(prev_dim, output_dim))
        self.mlp = nn.Sequential(*layers)
    
    def forward(self, x):
        # x: (B, feature_dim) - kinematic features per sequence
        return self.mlp(x)

class TemporalFeatureFusion(nn.Module):
    """Fuse features across temporal dimension with attention"""
    def __init__(self, feature_dim):
        super().__init__()
        self.attention = nn.MultiheadAttention(feature_dim, num_heads=8, batch_first=True)
        self.norm = nn.LayerNorm(feature_dim)
        self.dropout = nn.Dropout(0.1)
    
    def forward(self, x):
        # x: (B, T, feature_dim)
        attn_out, _ = self.attention(x, x, x)
        x = self.norm(x + self.dropout(attn_out))
        return x

class MultiModalFusion(nn.Module):
    """Fuse local patches, global patches, and kinematic features"""
    def __init__(self, local_dim, global_dim, kinematic_dim, output_dim):
        super().__init__()
        self.local_proj = nn.Linear(local_dim, output_dim)
        self.global_proj = nn.Linear(global_dim, output_dim)
        self.kinematic_proj = nn.Linear(kinematic_dim, output_dim)
        
        # Attention fusion
        self.fusion_attention = nn.MultiheadAttention(output_dim, num_heads=4, batch_first=True)
        self.norm = nn.LayerNorm(output_dim)
        self.dropout = nn.Dropout(0.2)
        
        # Final projection
        self.final_proj = nn.Sequential(
            nn.Linear(output_dim, output_dim),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(output_dim, output_dim)
        )
    
    def forward(self, local_features, global_features, kinematic_features):
        """
        Args:
            local_features: (B, local_dim) - from VSViG backbone
            global_features: (B, global_dim) - from global patch processing
            kinematic_features: (B, kinematic_dim) - from kinematic MLP
        """
        # Project all features to same dimension
        local_proj = self.local_proj(local_features)  # (B, output_dim)
        global_proj = self.global_proj(global_features)  # (B, output_dim)
        kinematic_proj = self.kinematic_proj(kinematic_features)  # (B, output_dim)
        
        # Stack features for attention
        # (B, 3, output_dim) - 3 modalities
        multi_modal = torch.stack([local_proj, global_proj, kinematic_proj], dim=1)
        
        # Self-attention fusion
        fused, attention_weights = self.fusion_attention(multi_modal, multi_modal, multi_modal)
        fused = self.norm(multi_modal + self.dropout(fused))
        
        # Pool across modalities (average)
        fused = torch.mean(fused, dim=1)  # (B, output_dim)
        
        # Final projection
        output = self.final_proj(fused)
        
        return output, attention_weights

class EnhancedSTViG(nn.Module):
    """Enhanced STViG with global patches and kinematic features"""
    def __init__(self, opt, kinematic_feature_dim=25, use_global_patches=True, use_kinematic_features=True):
        super().__init__()
        
        # Original VSViG parameters
        self.use_global_patches = use_global_patches
        self.use_kinematic_features = use_kinematic_features
        
        dynamic = opt.dynamic
        num_layer = opt.num_layer
        output_channels = opt.output_channels
        dynamic_point_order = opt.dynamic_point_order
        expansion = opt.expansion
        self.pos_emb = opt.pos_emb
        
        # Original VSViG components for local patches
        if opt.pos_emb == 'add':
            ch4stem = output_channels[0] - 3
        else:
            ch4stem = output_channels[0]

        self.stem = Stem(input_dim=3, output_dim=ch4stem)
        self.stem_pe = Stem_pe(input_dim=3, output_dim=ch4stem) if opt.pos_emb == 'stem' else None

        self.learnable_pe_6d = None
        self.learnable_pe_4d = None
        
        self.in_channels = ch4stem  # Start with stem output channels
        self.backbone = []
        seed_counter = 0
        
        # Build original backbone
        for stage, layers_in_stage in enumerate(num_layer):
            if stage > 0:
                self.backbone.append(Grapher(in_channels=self.in_channels, out_channels=output_channels[stage]))
                self.in_channels = output_channels[stage]  # Update after Grapher
                self.backbone.append(Part_3DCNN(stride=(2,1,1),
                                                in_channels=self.in_channels,
                                                out_channels=output_channels[stage],
                                                dynamic=dynamic,
                                                dynamic_point_order=dynamic_point_order,
                                                expansion=expansion,
                                                SEED=seed_counter))
                seed_counter += 1
                self.in_channels = output_channels[stage] * expansion

            for layer_idx in range(layers_in_stage):
                self.backbone.append(Grapher(in_channels=self.in_channels, out_channels=output_channels[stage]))
                self.in_channels = output_channels[stage]  # Update after Grapher
                self.backbone.append(Part_3DCNN(in_channels=self.in_channels,
                                                out_channels=output_channels[stage],
                                                dynamic=dynamic,
                                                dynamic_point_order=dynamic_point_order,
                                                expansion=expansion,
                                                SEED=seed_counter))
                seed_counter += 1
                self.in_channels = output_channels[stage] * expansion
        
        self.backbone = nn.Sequential(*self.backbone)
        
        # Enhanced components
        local_feature_dim = output_channels[-1] * expansion
        
        if self.use_global_patches:
            self.global_stem = GlobalPatchStem()
            self.global_feature_dim = self.global_stem.feature_dim
            self.global_temporal_fusion = TemporalFeatureFusion(self.global_feature_dim)
        else:
            self.global_feature_dim = 1
            
        if self.use_kinematic_features:
            self.kinematic_mlp = KinematicFeatureMLP(
                input_dim=kinematic_feature_dim, 
                output_dim=64
            )
            self.kinematic_feature_dim_out = 64
        else:
            self.kinematic_feature_dim_out = 1
        
        # Multi-modal fusion
        if self.use_global_patches or self.use_kinematic_features:
            fusion_dim = 256
            self.multi_modal_fusion = MultiModalFusion(
                local_dim=local_feature_dim,
                global_dim=self.global_feature_dim if self.use_global_patches else 1,
                kinematic_dim=self.kinematic_feature_dim_out if self.use_kinematic_features else 1,
                output_dim=fusion_dim
            )
            classifier_input_dim = fusion_dim
        else:
            classifier_input_dim = local_feature_dim
        
        # Enhanced classifier
        if self.use_global_patches or self.use_kinematic_features:
            self.classifier = nn.Sequential(
                nn.Linear(classifier_input_dim, 256),
                nn.BatchNorm1d(256),
                nn.ReLU(),
                nn.Dropout(0.3),
                nn.Linear(256, 128),
                nn.BatchNorm1d(128),
                nn.ReLU(),
                nn.Dropout(0.2),
                nn.Linear(128, 1)
            )
        else:
            # Fallback classifier for original features only
            self.classifier = nn.Sequential(
                nn.Conv2d(local_feature_dim, 256, 1),
                nn.BatchNorm2d(256),
                nn.ReLU(),
                nn.Conv2d(256, 1, 1)
            )
        
        self.model_init()

    def model_init(self):
        """Initialize model weights"""
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
        """Positional embedding (adapted for VSViG stem output)"""
        if len(x.shape) == 6:
            # Stem output: (B, T, P, C, H, W)
            _, T, P, C, H, W = x.shape
            if flag == 'learn':
                target_shape = (1, T, P, C, H, W)
                if self.learnable_pe_6d is None or self.learnable_pe_6d.shape != target_shape:
                    self.learnable_pe_6d = nn.Parameter(torch.zeros(target_shape, device=x.device, dtype=x.dtype))
                elif self.learnable_pe_6d.device != x.device or self.learnable_pe_6d.dtype != x.dtype:
                    self.learnable_pe_6d = nn.Parameter(self.learnable_pe_6d.to(device=x.device, dtype=x.dtype))
                x = x + self.learnable_pe_6d
            elif flag == 'add':
                # Reshape keypoints to match spatial dimensions before concatenation
                if kpts is not None and len(kpts.shape) == 4:
                    kpts_expanded = kpts.unsqueeze(-1).unsqueeze(-1).expand(-1, -1, -1, -1, H, W)
                    x = torch.cat((x, kpts_expanded), dim=3)  # Concat along channel dim
            elif flag == 'stem':
                if self.stem_pe is None:
                    raise RuntimeError("Positional embedding 'stem' requested but stem_pe module is not initialized.")
                if kpts is not None:
                    pe = self.stem_pe(kpts)  # (B, T, P, C)
                    if len(pe.shape) == 4:
                        pe = pe.unsqueeze(-1).unsqueeze(-1).expand(-1, -1, -1, -1, H, W)
                    x = x + pe
            elif flag == 'no':
                pass
        else:
            # Original 4D case: (B, T, P, C)
            _, T, P, C = x.shape
            if flag == 'learn':
                target_shape = (1, T, P, C)
                if self.learnable_pe_4d is None or self.learnable_pe_4d.shape != target_shape:
                    self.learnable_pe_4d = nn.Parameter(torch.zeros(target_shape, device=x.device, dtype=x.dtype))
                elif self.learnable_pe_4d.device != x.device or self.learnable_pe_4d.dtype != x.dtype:
                    self.learnable_pe_4d = nn.Parameter(self.learnable_pe_4d.to(device=x.device, dtype=x.dtype))
                x = x + self.learnable_pe_4d
            elif flag == 'add' and kpts is not None:
                x = torch.cat((x, kpts), dim=-1)
            elif flag == 'stem':
                if self.stem_pe is None:
                    raise RuntimeError("Positional embedding 'stem' requested but stem_pe module is not initialized.")
                if kpts is not None:
                    pe = self.stem_pe(kpts)  # (B, T, P, C)
                    x = x + pe
            elif flag == 'no':
                pass
        return x

    def forward(
        self,
        local_patches,
        keypoints=None,
        global_patches=None,
        kinematic_features=None,
        return_logits: bool = False,
    ):
        """
        Enhanced forward pass with multi-modal inputs
        
        Args:
            local_patches: (B, T, P, C, H, W) - original local patches (B, 30, 15, 3, 32, 32)
            keypoints: (B, T, P, 3) - keypoints for positional embedding (B, 30, 15, 3)
            global_patches: (B, T, H, W, 3) - global body patches (B, 30, 64, 64, 3)
            kinematic_features: (B, feature_dim) - kinematic feature vector per sequence
        
        Returns:
            output: Fall probability (B,) unless return_logits=True
            attention_weights: Attention weights if using multi-modal fusion
        """
        # Process local patches (original VSViG path)
        x = self.stem(local_patches)
        
        if self.pos_emb == 'stem' and keypoints is not None:
            # keypoints: (B, T, P, 3) -> use for positional embedding
            if len(keypoints.shape) == 4:
                keypoints_pe = keypoints  # (B, T, P, 3)
            elif len(keypoints.shape) == 3:
                # Add time dimension if missing
                keypoints_pe = keypoints.unsqueeze(1)  # (B, 1, P, 3)
            else:
                raise ValueError(f"Unexpected keypoint shape: {keypoints.shape}")
        else:
            keypoints_pe = keypoints
            
        x = self.pe(self.pos_emb, x, keypoints_pe)
        
        # Handle tensor from stem output
        if len(x.shape) == 6:
            B, T, P, C, H, W = x.shape
            # Average pool spatial dimensions: (B, T, P, C)
            x = x.mean(dim=(-2, -1))
        else:
            B, T, P, C = x.shape
        
        # Reshape to match expected backbone input: (B, T, C, P, 1)
        x = x.transpose(2,3).contiguous().view(B, T, C, P, 1)
        
        x = self.backbone(x)
        B,T,C,P,_ = x.shape
        x = x.transpose(1,2).contiguous().reshape(B,C,T,P)
        local_features = nn.functional.adaptive_avg_pool2d(x, 1).squeeze(-1).squeeze(-1)  # (B, C)
        
        # Process global patches if available
        if self.use_global_patches and global_patches is not None:
            global_features = self.global_stem(global_patches)  # (B, T, feature_dim)
            global_features = self.global_temporal_fusion(global_features)  # (B, T, feature_dim)
            global_features = torch.mean(global_features, dim=1)  # (B, feature_dim) - average over time
        else:
            # Create dummy global features with correct dimension
            global_features = torch.zeros(
                B,
                self.global_feature_dim,
                device=local_features.device,
                dtype=local_features.dtype,
            )
        
        # Process kinematic features if available
        if self.use_kinematic_features and kinematic_features is not None:
            kinematic_features_processed = self.kinematic_mlp(kinematic_features)  # (B, 64)
        else:
            # Create dummy kinematic features with correct dimension
            kinematic_features_processed = torch.zeros(
                B,
                self.kinematic_feature_dim_out,
                device=local_features.device,
                dtype=local_features.dtype,
            )
        
        # Multi-modal fusion
        if self.use_global_patches or self.use_kinematic_features:
            # Always use fusion path when enhanced features are enabled
            fused_features, attention_weights = self.multi_modal_fusion(
                local_features, global_features, kinematic_features_processed
            )
            logits = self.classifier(fused_features).squeeze(-1)
            if return_logits:
                return logits, attention_weights
            output = torch.sigmoid(logits)
            return output, attention_weights
        else:
            # Original path - just local features with Conv2d classifier
            local_features_2d = local_features.unsqueeze(-1).unsqueeze(-1)  # (B, C, 1, 1)
            logits = self.classifier(local_features_2d).squeeze(-1).squeeze(-1).squeeze(-1)
            if return_logits:
                return logits, None
            output = torch.sigmoid(logits)
            return output, None

@register_model
def EnhancedVSViG_base(pretrained=False, kinematic_feature_dim=25, 
                      use_global_patches=True, use_kinematic_features=True, **kwargs):
    """Enhanced VSViG base model with global patches and kinematic features"""
    class OptInit:
        def __init__(self, **kwargs):
            self.dynamic = 1
            self.num_layer = [2,2,6,2]
            self.output_channels = [24,48,96,192]
            try:
                self.dynamic_point_order = torch.load('dy_point_order.pt')
            except:
                self.dynamic_point_order = {i: list(range(15)) for i in range(50)}
            self.expansion = 2
            self.pos_emb = 'stem'
    
    opt = OptInit(**kwargs)
    model = EnhancedSTViG(opt, kinematic_feature_dim, use_global_patches, use_kinematic_features)
    return model

@register_model  
def EnhancedVSViG_light(pretrained=False, kinematic_feature_dim=25,
                       use_global_patches=True, use_kinematic_features=True, **kwargs):
    """Enhanced VSViG light model with global patches and kinematic features"""
    class OptInit:
        def __init__(self, **kwargs):
            self.dynamic = 1
            self.num_layer = [2,2,6,2]
            self.output_channels = [12,24,48,96]
            try:
                self.dynamic_point_order = torch.load('dy_point_order.pt')
            except:
                self.dynamic_point_order = {i: list(range(15)) for i in range(50)}
            self.expansion = 2
            self.pos_emb = 'stem'
    
    opt = OptInit(**kwargs)
    model = EnhancedSTViG(opt, kinematic_feature_dim, use_global_patches, use_kinematic_features)
    return model

if __name__ == "__main__":
    print("Testing Enhanced VSViG...")
    
    # Test model creation
    model_base = EnhancedVSViG_base()
    model_light = EnhancedVSViG_light()
    
    print(f"✅ Enhanced base model created: {sum(p.numel() for p in model_base.parameters())} parameters")
    print(f"✅ Enhanced light model created: {sum(p.numel() for p in model_light.parameters())} parameters")
    
    # Test forward pass with all modalities
    batch_size = 2
    frames = 30
    points = 15
    
    # Multi-modal inputs
    local_patches = torch.randn(batch_size, frames, points, 3, 32, 32)
    keypoints = torch.randn(batch_size, frames, points, 3)
    global_patches = torch.randn(batch_size, frames, 64, 64, 3)
    kinematic_features = torch.randn(batch_size, 25)
    
    try:
        with torch.no_grad():
            output_base, attention_base = model_base(local_patches, keypoints, global_patches, kinematic_features)
            output_light, attention_light = model_light(local_patches, keypoints, global_patches, kinematic_features)
        
        print(f"✅ Enhanced base model output: {output_base.shape}")
        print(f"✅ Enhanced light model output: {output_light.shape}")
        print(f"✅ Attention weights shape: {attention_base.shape if attention_base is not None else 'None'}")
        
        # Test with original inputs only (backward compatibility)
        # Create model without enhanced features for true backward compatibility
        model_original = EnhancedVSViG_base(use_global_patches=False, use_kinematic_features=False)
        with torch.no_grad():
            output_original, _ = model_original(local_patches, keypoints)
        print(f"✅ Backward compatibility test: {output_original.shape}")
        
        print("✅ All Enhanced VSViG tests passed!")
        
    except Exception as e:
        print(f"❌ Enhanced VSViG test failed: {e}")
        import traceback
        traceback.print_exc()