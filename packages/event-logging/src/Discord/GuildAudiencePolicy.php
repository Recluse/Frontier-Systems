<?php

declare(strict_types=1);

namespace Frontier\EventLogging\Discord;

/** Conservative text-channel ACL check: explicit everyone denial and only approved grants. */
final readonly class GuildAudiencePolicy
{
    /**
     * @param list<string> $staffRoles
     * @param list<string> $staffUsers
     * @param array<string, array{roles: list<string>, users: list<string>}> $conversations
     */
    public function __construct(private array $staffRoles, private array $staffUsers, private array $conversations = [])
    {
    }

    /**
     * @param list<string> $administratorRoles
     * @param list<array{id: string, type: int, allow_view: bool, deny_view: bool}> $overwrites
     */
    public function allows(string $guildId, array $administratorRoles, array $overwrites, array $route): bool
    {
        if ($route['audience'] === 'public') {
            return true;
        }
        if (array_diff($administratorRoles, $this->staffRoles) !== []) {
            return false; // Administrator bypasses channel overwrites.
        }
        $roles = $this->staffRoles;
        $users = $this->staffUsers;
        if ($route['audience'] === 'private') {
            $scope = $this->conversations[$route['scope_id']] ?? null;
            if ($scope === null) {
                return false;
            }
            $roles = array_merge($roles, $scope['roles']);
            $users = array_merge($users, $scope['users']);
        }
        $everyoneDenied = false;
        foreach ($overwrites as $overwrite) {
            if (!in_array($overwrite['type'], [0, 1], true)) {
                return false;
            }
            if ($overwrite['type'] === 0 && $overwrite['id'] === $guildId) {
                if ($overwrite['allow_view']) {
                    return false;
                }
                $everyoneDenied = $overwrite['deny_view'];
            }
            if ($overwrite['allow_view']) {
                $approved = $overwrite['type'] === 0 ? $roles : $users;
                if (!in_array($overwrite['id'], $approved, true)) {
                    return false;
                }
            }
        }
        return $everyoneDenied;
    }
}
