function info = watertank_git_info()
%WATERTANK_GIT_INFO Git commit hash and dirty-state of this repo, for run traceability.
% info.commit: current HEAD commit SHA ('' if not a git repo / git unavailable)
% info.dirty:  true if there are uncommitted changes (working tree != HEAD)

repoDir = fileparts(mfilename('fullpath'));
info = struct('commit', '', 'dirty', false);

[status, out] = system(sprintf('git -C "%s" rev-parse HEAD', repoDir));
if status == 0
    info.commit = strtrim(out);
end

[status2, out2] = system(sprintf('git -C "%s" status --porcelain', repoDir));
if status2 == 0
    info.dirty = ~isempty(strtrim(out2));
end
end
