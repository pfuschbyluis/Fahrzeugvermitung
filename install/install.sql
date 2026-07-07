-- ============================================================
-- OPTIONAL – wird NUR benötigt, wenn Config.UseDatabase = true
-- Dient ausschließlich der Protokollierung abgeschlossener
-- Vermietungen (Statistik/Übersicht). Für den normalen Betrieb
-- des Scripts ist KEINE Datenbank erforderlich.
-- ============================================================

CREATE TABLE IF NOT EXISTS `MB_Fahrzeugvermitung_history` (
    `id`         INT NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(64)  NOT NULL,
    `location`   VARCHAR(64)  NOT NULL,
    `vehicle`    VARCHAR(64)  NOT NULL,
    `plate`      VARCHAR(16)  NOT NULL,
    `price`      INT NOT NULL,
    `minutes`    INT NOT NULL,
    `payment`    VARCHAR(16)  NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
