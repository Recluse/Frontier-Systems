<?php

declare(strict_types=1);

namespace Frontier\EventLogging\Discord;

use Discord\Discord;

/** Invoke only after a complete ready guild cache. Unsupported/missing channel records reject. */
final readonly class DiscordGuildAudienceVerifier
{
    public function __construct(private Discord $discord, private string $guildId, private GuildAudiencePolicy $policy)
    {
    }

    public function __invoke(object $channel, array $route): bool
    {
        if ((string) $channel->guild_id !== $this->guildId || !in_array($channel->type, [0, 5], true)) {
            return false; // Threads, DMs and inherited/incomplete ACL shapes need their own verifier.
        }
        $guild = $this->discord->guilds->get('id', $this->guildId);
        if ($guild === null || count($guild->roles) === 0) {
            return false;
        }
        $administrators = [];
        foreach ($guild->roles as $role) {
            if ($role->permissions->administrator) {
                $administrators[] = (string) $role->id;
            }
        }
        $overwrites = [];
        foreach ($channel->permission_overwrites as $overwrite) {
            $overwrites[] = ['id' => (string) $overwrite->id, 'type' => (int) $overwrite->type,
                'allow_view' => (bool) $overwrite->allow->view_channel, 'deny_view' => (bool) $overwrite->deny->view_channel];
        }
        return $this->policy->allows($this->guildId, $administrators, $overwrites, $route);
    }
}
