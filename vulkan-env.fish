# ============================================================================
#  vulkan-env.fish — fish version of vulkan-env.sh
#
#  USAGE (in fish):
#    source /path/to/repo/vulkan-env.fish
#    source /path/to/repo/vulkan-env.fish --mesa 26.0.4
#    source /path/to/repo/vulkan-env.fish --mesa 25.3.5 --hud fps
#
#  It is a wrapper: it computes the environment with vulkan-env.sh (--show)
#  and imports it into the fish session (VK_DRIVER_FILES, VK_ICD_FILENAMES,
#  LD_LIBRARY_PATH and, if requested, DXVK_HUD). The repository is located
#  automatically, so its name and location do not matter.
# ============================================================================

set -l _vkdir (dirname (status --current-filename))
set -l _vkout (bash "$_vkdir/vulkan-env.sh" $argv --show)
if test $status -ne 0
    echo "vulkan-env.fish: could not prepare the environment" >&2
else
    for _vkline in $_vkout
        set -l _kv (string split -m1 '=' -- $_vkline)
        if test (count $_kv) -eq 2
            set -gx $_kv[1] $_kv[2]
        end
    end
    echo "vulkan-env.fish: Mesa $VULKAN_MESA_ACTIVE active (VK_DRIVER_FILES=$VK_DRIVER_FILES)"
end
