package com.bankpulse.split;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import java.time.Duration;
import org.springframework.stereotype.Component;

@Component
public class SocialSplitMetrics {

    private final Counter sessionsInitiated;
    private final Counter sessionsCompleted;

    private final Counter participantsAdded;
    private final Counter participantsAuthorized;

    private final Counter closeAttempts;
    private final Counter closeBlocked;

    private final Counter settlementsValid;
    private final Counter settlementsInvalid;

    private final Timer closeDuration;

    public SocialSplitMetrics(MeterRegistry registry) {

        this.sessionsInitiated = Counter.builder(
                "bankpulse.social_split.sessions.initiated")
            .description("Total number of Social Split sessions initiated")
            .register(registry);

        this.sessionsCompleted = Counter.builder(
                "bankpulse.social_split.sessions.completed")
            .description("Total number of Social Split sessions successfully completed")
            .register(registry);

        this.participantsAdded = Counter.builder(
                "bankpulse.social_split.participants.added")
            .description("Total number of participants added to Social Split sessions")
            .register(registry);

        this.participantsAuthorized = Counter.builder(
                "bankpulse.social_split.participants.authorized")
            .description("Total number of participants that authorized their participation")
            .register(registry);

        this.closeAttempts = Counter.builder(
                "bankpulse.social_split.sessions.close.attempts")
            .description("Total number of Social Split close attempts")
            .register(registry);

        this.closeBlocked = Counter.builder(
                "bankpulse.social_split.sessions.close.blocked")
            .description("Close attempts blocked because the business invariant was not satisfied")
            .register(registry);

        this.settlementsValid = Counter.builder(
                "bankpulse.social_split.settlements.valid")
            .description("Completed Social Split settlements whose shares match the total amount")
            .register(registry);

        this.settlementsInvalid = Counter.builder(
                "bankpulse.social_split.settlements.invalid")
            .description("Completed Social Split settlements whose shares do not match the total amount")
            .register(registry);

        this.closeDuration = Timer.builder(
                "bankpulse.social_split.sessions.close.duration")
            .description("Time from Social Split creation until successful completion")
            .register(registry);
    }

    public void sessionCreated() {
        sessionsInitiated.increment();
    }

    public void sessionCompleted(Duration duration) {
        sessionsCompleted.increment();
        closeDuration.record(duration);
    }

    public void participantAdded() {
        participantsAdded.increment();
    }

    public void participantAuthorized() {
        participantsAuthorized.increment();
    }

    public void closeAttempt() {
        closeAttempts.increment();
    }

    public void closeBlocked() {
        closeBlocked.increment();
    }

    public void settlementValid() {
        settlementsValid.increment();
    }

    public void settlementInvalid() {
        settlementsInvalid.increment();
    }
}