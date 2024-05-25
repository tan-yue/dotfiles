if status is-interactive
    # Commands to run in interactive sessions can go here
    vf activate base
    fish_ssh_agent
    set -gx PATH $PATH /usr/local/cuda-11.7/bin
    set -gx PATH $PATH ~/squashfs-root/usr/bin
    set -gx PATH $PATH ~/.bazel
    set -gx PATH $PATH /opt/mellanox/doca/tools
    set -gx LD_LIBRARY_PATH $LD_LIBRARY_PATH /usr/local/cuda-11.7/lib64
    set -gx LD_LIBRARY_PATH $LD_LIBRARY_PATH ~/eZT/nccl_eZTChannel/build
    set -gx LD_LIBRARY_PATH $LD_LIBRARY_PATH /opt/mellanox/doca/lib
    set -gx LD_LIBRARY_PATH $LD_LIBRARY_PATH /opt/mellanox/doca/lib
    set -gx LD_LIBRARY_PATH $LD_LIBRARY_PATH ~/nccl/build/lib
end
